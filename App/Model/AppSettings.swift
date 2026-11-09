import Foundation
import InkyCore
import InkyHotkeys
import InkyStorage
import InkyTranscription
import Observation

/// Position de la pastille à l'écran.
enum OverlayPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: "En haut à gauche"
        case .top: "En haut"
        case .topRight: "En haut à droite"
        case .left: "À gauche"
        case .right: "À droite"
        case .bottomLeft: "En bas à gauche"
        case .bottom: "En bas (centre)"
        case .bottomRight: "En bas à droite"
        }
    }
}

/// Tous les réglages de l'app, sauvegardés dans `UserDefaults`.
///
/// Chaque propriété relit sa valeur au démarrage et l'écrit dès qu'elle change
/// (`didSet`). Grâce à `@Observable`, l'interface et le contrôleur réagissent
/// immédiatement à toute modification.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    // — Interrupteur général —
    /// Faux : Inky ne réagit plus aux raccourcis et la pastille disparaît.
    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }

    // — Raccourcis —
    var pushToTalkShortcut: Shortcut { didSet { save(pushToTalkShortcut, Keys.pushToTalk) } }
    var handsFreeShortcut: Shortcut { didSet { save(handsFreeShortcut, Keys.handsFree) } }

    // — Audio —
    /// UID du micro choisi ; `nil` = micro par défaut du système.
    var inputDeviceUID: String? { didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDevice) } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: Keys.playSounds) } }

    // — Transcription —
    var selectedModelID: String { didSet { defaults.set(selectedModelID, forKey: Keys.model) } }
    var language: DictationLanguage { didSet { save(language, Keys.language) } }

    // — Mise en forme —
    var formatting: FormattingOptions { didSet { save(formatting, Keys.formatting) } }
    /// Ajouter une espace si on dicte juste après un mot.
    var smartSpacing: Bool { didSet { defaults.set(smartSpacing, forKey: Keys.smartSpacing) } }

    // — Insertion —
    var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) } }
    /// Délai avant restauration du presse-papier, en millisecondes.
    var restoreDelayMs: Int { didSet { defaults.set(restoreDelayMs, forKey: Keys.restoreDelay) } }

    // — Pastille —
    var overlayPosition: OverlayPosition { didSet { save(overlayPosition, Keys.overlayPosition) } }
    /// Afficher la pastille pendant l'enregistrement et la transcription.
    var overlayEnabled: Bool { didSet { defaults.set(overlayEnabled, forKey: Keys.overlayEnabled) } }
    /// Garder une petite pastille visible au repos (y compris en plein écran).
    var overlayAlwaysVisible: Bool { didSet { defaults.set(overlayAlwaysVisible, forKey: Keys.overlayAlways) } }
    /// Afficher la durée de l'enregistrement dans la pastille.
    var overlayShowsTimer: Bool { didSet { defaults.set(overlayShowsTimer, forKey: Keys.overlayTimer) } }

    // — Historique —
    var historyRetention: HistoryRetention { didSet { save(historyRetention, Keys.retention) } }
    var keepAudio: Bool { didSet { defaults.set(keepAudio, forKey: Keys.keepAudio) } }

    // — Mises à jour —
    var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheck) } }
    var autoInstallUpdates: Bool { didSet { defaults.set(autoInstallUpdates, forKey: Keys.autoInstall) } }

    // — Premier lancement —
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    var hasSeenTutorial: Bool { didSet { defaults.set(hasSeenTutorial, forKey: Keys.tutorial) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        pushToTalkShortcut = Self.load(Keys.pushToTalk, from: defaults) ?? .defaultPushToTalk
        handsFreeShortcut = Self.load(Keys.handsFree, from: defaults) ?? .defaultHandsFree
        inputDeviceUID = defaults.string(forKey: Keys.inputDevice)
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        selectedModelID = defaults.string(forKey: Keys.model) ?? ModelCatalog.recommended.id
        language = Self.load(Keys.language, from: defaults) ?? .french
        formatting = Self.load(Keys.formatting, from: defaults) ?? FormattingOptions()
        smartSpacing = defaults.object(forKey: Keys.smartSpacing) as? Bool ?? true
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        restoreDelayMs = defaults.object(forKey: Keys.restoreDelay) as? Int ?? 350
        overlayPosition = Self.load(Keys.overlayPosition, from: defaults) ?? .bottom
        overlayEnabled = defaults.object(forKey: Keys.overlayEnabled) as? Bool ?? true
        overlayAlwaysVisible = defaults.object(forKey: Keys.overlayAlways) as? Bool ?? true
        overlayShowsTimer = defaults.object(forKey: Keys.overlayTimer) as? Bool ?? true
        autoCheckUpdates = defaults.object(forKey: Keys.autoCheck) as? Bool ?? true
        autoInstallUpdates = defaults.object(forKey: Keys.autoInstall) as? Bool ?? false
        historyRetention = Self.load(Keys.retention, from: defaults) ?? .oneMonth
        keepAudio = defaults.object(forKey: Keys.keepAudio) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        hasSeenTutorial = defaults.bool(forKey: Keys.tutorial)
    }

    // MARK: - Persistance des types complexes (encodés en JSON)

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private enum Keys {
        static let pushToTalk = "shortcut.pushToTalk"
        static let handsFree = "shortcut.handsFree"
        static let inputDevice = "audio.inputDeviceUID"
        static let playSounds = "audio.playSounds"
        static let model = "transcription.model"
        static let language = "transcription.language"
        static let enabled = "general.enabled"
        static let formatting = "formatting.options"
        static let smartSpacing = "formatting.smartSpacing"
        static let overlayEnabled = "overlay.enabled"
        static let overlayAlways = "overlay.alwaysVisible"
        static let overlayTimer = "overlay.showsTimer"
        static let autoCheck = "updates.autoCheck"
        static let autoInstall = "updates.autoInstall"
        static let tutorial = "tutorial.seen"
        static let restoreClipboard = "insertion.restoreClipboard"
        static let restoreDelay = "insertion.restoreDelayMs"
        static let overlayPosition = "overlay.position"
        static let retention = "history.retention"
        static let keepAudio = "history.keepAudio"
        static let onboarding = "onboarding.completed"
    }
}
