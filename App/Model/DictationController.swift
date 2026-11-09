import AppKit
import InkyAudio
import InkyCore
import InkyHotkeys
import InkyInsertion
import InkyStorage
import InkyTranscription
import Observation
import os

/// Le chef d'orchestre d'une dictée.
///
/// Il relie les modules entre eux sans qu'ils se connaissent : les raccourcis
/// déclenchent l'enregistrement, l'audio part au moteur, le texte passe par la
/// mise en forme puis va à l'inserteur et à l'historique. Chaque module n'est vu
/// qu'à travers son API (ou son protocole pour le moteur et l'inserteur), ce qui
/// permet de les remplacer.
///
/// Machine à états :
///
///     idle ─raccourci─▶ preparing ─micro prêt─▶ recording ─relâché─▶ transcribing ─▶ idle
///                         │                       │                  (mise en forme,
///                         └──── ⎋ / autre touche ─┴─▶ idle (annulé)   insertion, historique)
@MainActor
@Observable
final class DictationController {
    enum Mode: Equatable { case pushToTalk, handsFree }

    enum Phase: Equatable {
        case idle
        /// Le micro démarre (50 à 200 ms, parfois plus en Bluetooth).
        case preparing(Mode)
        case recording(Mode)
        case transcribing

        var mode: Mode? {
            switch self {
            case .preparing(let mode), .recording(let mode): mode
            default: nil
            }
        }
    }

    enum ModelStatus: Equatable {
        case notInstalled
        case loading(String)
        case ready(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var modelStatus: ModelStatus = .notInstalled
    /// Dernier texte dicté (accessible depuis le menu, au cas où l'insertion a échoué).
    private(set) var lastTranscript: String?
    private(set) var hotkeysActive = false
    /// Délai de démarrage du micro lors de la dernière dictée (diagnostic « 1re syllabe »).
    private(set) var lastMicStartupDelay: TimeInterval?

    // Dépendances
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let permissions: PermissionsManager
    @ObservationIgnored let models: ModelManager
    @ObservationIgnored let vocabulary: VocabularyStore
    @ObservationIgnored let history: HistoryStore?
    @ObservationIgnored let overlay = OverlayController()
    @ObservationIgnored let hotkeys = EventTapMonitor()
    @ObservationIgnored private let engine: any TranscriptionEngine
    @ObservationIgnored private let inserter: any TextInserter
    @ObservationIgnored private let recorder = AudioRecorder()

    // État d'une dictée en cours
    @ObservationIgnored private var recordingStartedAt: Date?
    @ObservationIgnored private var targetApp: NSRunningApplication?
    @ObservationIgnored private var maxDurationTask: Task<Void, Never>?
    @ObservationIgnored private var loadedModelID: String?
    @ObservationIgnored private let logger = Logger(subsystem: "com.byteonedev.inky", category: "dictation")

    /// Sécurité : un enregistrement mains libres oublié s'arrête tout seul.
    private let maxRecordingDuration: Duration = .seconds(600)
    /// En dessous, c'est un appui accidentel : on ignore.
    private let minRecordingDuration: TimeInterval = 0.3
    /// Pic sonore minimal : en dessous, on considère qu'il n'y a pas eu de voix.
    private let silencePeakThreshold: Float = 0.015

    init(
        settings: AppSettings,
        permissions: PermissionsManager,
        models: ModelManager,
        vocabulary: VocabularyStore,
        history: HistoryStore?,
        engine: any TranscriptionEngine = WhisperKitEngine(),
        inserter: any TextInserter = PasteboardInserter()
    ) {
        self.settings = settings
        self.permissions = permissions
        self.models = models
        self.vocabulary = vocabulary
        self.history = history
        self.engine = engine
        self.inserter = inserter

        // Le callback de l'event tap doit rendre la main en quelques
        // microsecondes : on traite l'action juste après, dans une tâche à part
        // (démarrer le micro prend 50 à 200 ms).
        hotkeys.onAction = { [weak self] action in
            Task { @MainActor in self?.handle(action) }
        }
        recorder.onLevel = { [weak self] level in
            // Thread audio → thread principal.
            Task { @MainActor in self?.overlay.model.push(level: level) }
        }
        recorder.onReady = { [weak self] delay in
            Task { @MainActor in self?.microphoneReady(after: delay) }
        }
        overlay.model.onClick = { [weak self] in self?.overlayClicked() }
    }

    // MARK: - Démarrage

    /// À appeler une fois au lancement de l'app.
    func start() {
        applyShortcuts()
        applyOverlaySettings()
        startHotkeysIfPossible()
        Task { await loadSelectedModel() }
        purgeHistory()

        // Réagir aux changements de réglages et d'état, sans que les vues aient
        // à prévenir le contrôleur.
        observe { [settings] in (settings.pushToTalkShortcut, settings.handsFreeShortcut) } then: { [weak self] in
            self?.applyShortcuts()
        }
        observe { [settings] in settings.selectedModelID } then: { [weak self] in
            Task { await self?.loadSelectedModel() }
        }
        observe { [models] in models.installed } then: { [weak self] in
            // Un téléchargement vient de finir (ou un modèle a été supprimé).
            Task { await self?.loadSelectedModel() }
        }
        observe { [permissions] in permissions.accessibility } then: { [weak self] in
            self?.startHotkeysIfPossible()
        }
        observe { [settings] in settings.isEnabled } then: { [weak self] in
            self?.enabledChanged()
        }
        observe { [settings] in
            (settings.overlayPosition, settings.overlayEnabled, settings.overlayAlwaysVisible, settings.overlayShowsTimer)
        } then: { [weak self] in
            self?.applyOverlaySettings()
        }
        observe { [settings] in settings.historyRetention } then: { [weak self] in
            self?.purgeHistory()
        }
        // Purge périodique (toutes les heures) pour une app qui reste ouverte des jours.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.purgeHistory()
            }
        }
    }

    /// Le tap clavier exige l'Accessibilité : on (re)tente dès qu'elle est accordée.
    func startHotkeysIfPossible() {
        if permissions.accessibility && settings.isEnabled {
            hotkeysActive = hotkeys.start()
        } else {
            hotkeys.stop()
            hotkeysActive = false
        }
    }

    private func enabledChanged() {
        if !settings.isEnabled { cancelRecording(silently: true) }
        startHotkeysIfPossible()
        applyOverlaySettings()
    }

    private func applyShortcuts() {
        hotkeys.stateMachine.pushToTalk = settings.pushToTalkShortcut
        hotkeys.stateMachine.handsFree = settings.handsFreeShortcut
        hotkeys.stateMachine.reset()
        overlay.model.hint = "Maintiens \(settings.pushToTalkShortcut.displayString) pour dicter, ou clique pour démarrer"
    }

    private func applyOverlaySettings() {
        overlay.position = settings.overlayPosition
        overlay.showsWhileDictating = settings.overlayEnabled
        overlay.alwaysVisible = settings.overlayAlwaysVisible
        overlay.isEnabled = settings.isEnabled
        overlay.model.showsTimer = settings.overlayShowsTimer
        overlay.refresh()
    }

    // MARK: - Modèle

    func loadSelectedModel() async {
        let id = settings.selectedModelID
        guard models.isInstalled(id) else {
            loadedModelID = nil
            await engine.unload()
            modelStatus = .notInstalled
            return
        }
        // Déjà chargé (ou en cours) : rien à faire.
        if loadedModelID == id { return }
        loadedModelID = id
        let name = ModelCatalog.info(for: id)?.displayName ?? id
        modelStatus = .loading(name)
        do {
            try await engine.load(modelAt: models.folder(for: id))
            // L'utilisateur a pu changer de modèle pendant le chargement.
            if settings.selectedModelID == id { modelStatus = .ready(name) }
        } catch {
            logger.error("Chargement du modèle impossible : \(error.localizedDescription, privacy: .public)")
            modelStatus = .failed(error.localizedDescription)
            loadedModelID = nil
        }
    }

    // MARK: - Raccourcis et clic sur la pastille

    private func handle(_ action: HotkeyAction) {
        guard settings.isEnabled else { return }
        switch (action, phase.mode) {
        case (.pushToTalkBegan, nil) where phase == .idle:
            startRecording(.pushToTalk)
        case (.pushToTalkEnded, .pushToTalk?):
            finishRecording()
        case (.pushToTalkCancelled, .pushToTalk?):
            cancelRecording()
        case (.handsFreeToggled, nil) where phase == .idle:
            startRecording(.handsFree)
        case (.handsFreeToggled, _?):
            finishRecording()
        case (.cancel, _?):
            cancelRecording()
        default:
            break // ex. raccourci pressé pendant une transcription : ignoré
        }
    }

    private func overlayClicked() {
        switch phase {
        case .idle: startRecording(.handsFree)
        case .preparing, .recording: finishRecording()
        case .transcribing: break
        }
    }

    // MARK: - Enregistrement

    func startRecording(_ mode: Mode) {
        guard phase == .idle, settings.isEnabled else { return }

        // Pré-requis, avec un message clair pour chaque cas.
        permissions.refresh()
        guard permissions.microphone == .granted else {
            overlay.flash("Accès au micro refusé. Ouvre les réglages d'Inky.", isError: true)
            if permissions.microphone == .notDetermined { Task { await permissions.requestMicrophone() } }
            return
        }
        switch modelStatus {
        case .ready: break
        case .loading: overlay.flash("Modèle en cours de chargement, patiente quelques secondes…"); return
        case .notInstalled: overlay.flash("Aucun modèle installé : Réglages › Modèles.", isError: true); return
        case .failed: overlay.flash("Le modèle n'a pas pu être chargé.", isError: true); return
        }

        // On retient l'app cible maintenant : c'est là que l'utilisateur dicte.
        targetApp = NSWorkspace.shared.frontmostApplication

        // La pastille passe en « Attends… » AVANT de démarrer le micro.
        phase = .preparing(mode)
        overlay.show(.preparing)
        do {
            try recorder.start(deviceUID: settings.inputDeviceUID)
        } catch {
            phase = .idle
            overlay.flash(error.localizedDescription, isError: true)
            return
        }
        recordingStartedAt = Date()
        hotkeys.stateMachine.escapeCancels = true

        maxDurationTask = Task { [weak self, maxRecordingDuration] in
            try? await Task.sleep(for: maxRecordingDuration)
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    /// Premier tampon audio reçu : on peut parler.
    private func microphoneReady(after delay: TimeInterval) {
        guard case .preparing(let mode) = phase else { return }
        lastMicStartupDelay = delay
        logger.info("Micro prêt en \(Int(delay * 1000), privacy: .public) ms")
        phase = .recording(mode)
        overlay.show(.recording(handsFree: mode == .handsFree, startedAt: Date()))
        playSound("Tink")
    }

    func cancelRecording(silently: Bool = false) {
        guard phase.mode != nil else { return }
        recorder.cancel()
        endRecordingState()
        phase = .idle
        if silently { overlay.hide() } else { overlay.flash("Annulé", duration: .seconds(0.8)) }
    }

    func finishRecording() {
        if case .preparing = phase {
            // Relâché avant même que le micro soit prêt : appui accidentel.
            cancelRecording(silently: true)
            return
        }
        guard case .recording = phase else { return }
        let clip = recorder.stop()
        let stoppedAt = Date()
        endRecordingState()
        playSound("Pop")

        guard clip.duration >= minRecordingDuration else {
            phase = .idle
            overlay.hide()
            return
        }
        guard clip.peak >= silencePeakThreshold else {
            phase = .idle
            overlay.flash("Aucune voix détectée (vérifie le micro choisi).", isError: true)
            return
        }

        phase = .transcribing
        overlay.show(.transcribing)
        Task { await transcribeAndInsert(clip, stoppedAt: stoppedAt) }
    }

    private func endRecordingState() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
        hotkeys.stateMachine.escapeCancels = false
    }

    // MARK: - Transcription → mise en forme → insertion → historique

    private func transcribeAndInsert(_ clip: AudioClip, stoppedAt: Date) async {
        defer { phase = .idle }
        let options = TranscriptionOptions(language: settings.language, prompt: vocabulary.prompt)

        let output: TranscriptionOutput
        do {
            output = try await engine.transcribe(clip, options: options)
        } catch {
            logger.error("Transcription échouée : \(error.localizedDescription, privacy: .public)")
            overlay.flash("Échec de la transcription.", isError: true)
            return
        }

        let context = ProcessingContext(
            appBundleID: targetApp?.bundleIdentifier,
            appName: targetApp?.localizedName,
            language: output.language
        )
        var text = TextPipeline(options: settings.formatting, rules: vocabulary.rules).format(output.text, context: context)
        guard !text.isEmpty else {
            overlay.flash("Rien de compréhensible n'a été entendu.")
            return
        }
        if settings.smartSpacing, AXIsProcessTrusted() {
            text = FocusedTextContext.applySmartSpacing(to: text, previous: FocusedTextContext.characterBeforeCursor())
        }
        lastTranscript = text

        // Insertion
        if let pasteboardInserter = inserter as? PasteboardInserter {
            pasteboardInserter.restoreClipboard = settings.restoreClipboard
            pasteboardInserter.restoreDelay = .milliseconds(settings.restoreDelayMs)
        }
        do {
            try await inserter.insert(text)
            overlay.hide()
        } catch .secureInputActive {
            overlay.flash("Champ sécurisé : texte copié, colle-le avec ⌘V.", isError: true, duration: .seconds(4))
        } catch .accessibilityNotGranted {
            overlay.flash("Accessibilité non autorisée : texte copié, colle-le avec ⌘V.", isError: true, duration: .seconds(4))
        } catch {
            overlay.flash("Insertion impossible : texte copié dans le presse-papier.", isError: true)
        }

        let latency = Date().timeIntervalSince(stoppedAt)
        logger.info("Dictée : \(clip.duration, format: .fixed(precision: 1), privacy: .public) s audio, transcription \(output.processingTime, format: .fixed(precision: 2), privacy: .public) s, fin de parole → insertion \(latency, format: .fixed(precision: 2), privacy: .public) s")

        saveToHistory(text: text, raw: output.text, clip: clip, output: output)
    }

    private func saveToHistory(text: String, raw: String, clip: AudioClip, output: TranscriptionOutput) {
        guard let history, settings.historyRetention != .never else { return }
        let keepAudio = settings.keepAudio
        let entry = HistoryEntry(
            text: text,
            rawText: raw,
            audioDuration: clip.duration,
            processingTime: output.processingTime,
            modelID: settings.selectedModelID,
            language: output.language,
            appName: targetApp?.localizedName,
            appBundleID: targetApp?.bundleIdentifier,
            audioFileName: keepAudio ? history.newAudioFileName() : nil
        )
        // Encodage audio + écriture SQLite hors du thread principal.
        Task.detached(priority: .utility) { [logger] in
            do {
                if let name = entry.audioFileName {
                    try AudioFileWriter.writeM4A(clip, to: history.audioDirectory.appending(path: name))
                }
                try history.add(entry)
            } catch {
                logger.error("Historique : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func purgeHistory() {
        guard let history else { return }
        let retention = settings.historyRetention
        Task.detached(priority: .background) {
            try? history.purge(retention: retention)
        }
    }

    // MARK: - Utilitaires

    private func playSound(_ name: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Appelle `action` à chaque changement de la valeur lue dans `value`.
    ///
    /// `withObservationTracking` enregistre les propriétés `@Observable` lues
    /// dans `value`, et appelle `onChange` **une seule fois** à leur prochain
    /// changement : on se réabonne donc à chaque fois (d'où la récursion).
    private func observe<T>(_ value: @escaping @MainActor () -> T, then action: @escaping @MainActor () -> Void) {
        withObservationTracking {
            _ = value()
        } onChange: {
            Task { @MainActor [weak self] in
                action()
                self?.observe(value, then: action)
            }
        }
    }
}
