import InkyAudio
import InkyCore
import InkyStorage
import InkyTranscription
import SwiftUI

/// Fenêtre des réglages, en onglets.
struct SettingsView: View {
    let app: AppModel

    var body: some View {
        TabView {
            GeneralSettings(app: app)
                .tabItem { Label("Général", systemImage: "gearshape") }
            AudioSettings(settings: app.settings, controller: app.controller)
                .tabItem { Label("Audio", systemImage: "mic") }
            ModelSettings(app: app)
                .tabItem { Label("Modèles", systemImage: "cpu") }
            DictionarySettings(vocabulary: app.vocabulary)
                .tabItem { Label("Dictionnaire", systemImage: "character.book.closed") }
            FormattingSettings(settings: app.settings)
                .tabItem { Label("Mise en forme", systemImage: "text.badge.checkmark") }
            HistorySettings(app: app)
                .tabItem { Label("Historique", systemImage: "clock") }
            AboutView(app: app)
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 660, height: 520)
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Inky activé", isOn: $settings.isEnabled)
                Text("Désactivé : les raccourcis ne font plus rien et la pastille disparaît. Aussi accessible depuis le menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Raccourcis") {
                LabeledContent("Push-to-talk (maintenir)") {
                    ShortcutRecorderView(shortcut: $settings.pushToTalkShortcut, monitor: app.controller.hotkeys)
                }
                LabeledContent("Mains libres (appuyer)") {
                    ShortcutRecorderView(shortcut: $settings.handsFreeShortcut, monitor: app.controller.hotkeys)
                }
                Text("Pendant un enregistrement, ⎋ annule. Si tu presses une autre touche pendant le push-to-talk (ex. ⌃⌘Q), la dictée est annulée et la touche fonctionne normalement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !app.controller.hotkeysActive {
                    Label("Raccourcis inactifs : autorisation Accessibilité requise.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Ouvrir l'assistant d'autorisations") { app.windows.show(.onboarding) }
                }
            }

            Section("Pastille") {
                Toggle("Toujours visible, même en plein écran", isOn: $settings.overlayAlwaysVisible)
                Text("Une petite capsule discrète reste à l'écran. Clique dessus pour démarrer ou arrêter une dictée mains libres.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Afficher pendant la dictée (forme d'onde, transcription)", isOn: $settings.overlayEnabled)
                Toggle("Afficher la durée de l'enregistrement", isOn: $settings.overlayShowsTimer)
                    .disabled(!settings.overlayEnabled)
                Picker("Position", selection: $settings.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { Text($0.displayName).tag($0) }
                }
                Button("Aperçu") {
                    app.controller.overlay.flash("Aperçu de la pastille")
                }
            }

            Section("Insertion") {
                Toggle("Restaurer le presse-papier après le collage", isOn: $settings.restoreClipboard)
                if settings.restoreClipboard {
                    Stepper("Délai avant restauration : \(settings.restoreDelayMs) ms", value: $settings.restoreDelayMs, in: 100...2000, step: 50)
                    Text("Augmente ce délai si une app colle parfois l'ancien contenu du presse-papier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio

private struct AudioSettings: View {
    let settings: AppSettings
    let controller: DictationController
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Micro") {
                Picker("Périphérique d'entrée", selection: $settings.inputDeviceUID) {
                    Text("Micro par défaut du système").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                    // Micro choisi mais débranché : on le garde affiché.
                    if let uid = settings.inputDeviceUID, !devices.contains(where: { $0.uid == uid }) {
                        Text("Périphérique déconnecté").tag(Optional(uid))
                    }
                }
                Button("Actualiser la liste") { devices = AudioDevices.inputDevices() }
                Text("Évite le micro des AirPods : macOS bascule alors le casque en mode « appel », avec un son dégradé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Démarrage du micro (dernière dictée)") {
                    if let delay = controller.lastMicStartupDelay {
                        Text("\(Int(delay * 1000)) ms").monospacedDigit()
                    } else {
                        Text("—")
                    }
                }
            } header: {
                Text("Diagnostic")
            } footer: {
                Text("Temps entre l'appui sur le raccourci et le moment où le micro enregistre vraiment. La pastille affiche « Attends… » pendant ce délai : commence à parler quand elle passe au rouge. Au-delà de 300 ms (souvent en Bluetooth), la première syllabe risquait d'être coupée.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Retour sonore") {
                Toggle("Jouer un son quand le micro est prêt et à la fin", isOn: $settings.playSounds)
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputDevices() }
    }
}

// MARK: - Modèles

private struct ModelSettings: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        let models = app.models
        Form {
            Section("Langue") {
                Picker("Langue de dictée", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Forcer le français reste efficace quand tu glisses des mots anglais : Whisper les écrit correctement. La détection automatique se trompe plus souvent sur les phrases courtes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ModelCatalog.models) { info in
                    ModelRow(info: info, app: app)
                }
            } header: {
                Text("Modèles Whisper")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText).font(.caption)
                    if let error = models.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch app.controller.modelStatus {
        case .notInstalled: "Le modèle sélectionné n'est pas installé."
        case .loading(let name): "Chargement de \(name)… (la toute première fois, l'optimisation pour ta puce peut prendre 1 à 2 minutes)"
        case .ready(let name): "Modèle actif : \(name)"
        case .failed(let error): "Erreur : \(error)"
        }
    }
}

private struct ModelRow: View {
    let info: WhisperModelInfo
    let app: AppModel

    var body: some View {
        let models = app.models
        let installed = models.isInstalled(info.id)
        let selected = app.settings.selectedModelID == info.id

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(installed ? Color.accentColor : Color.secondary)
                .onTapGesture { if installed { app.settings.selectedModelID = info.id } }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(info.displayName).fontWeight(selected ? .semibold : .regular)
                    if info.isRecommended {
                        Text("Recommandé").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                Text("\(info.summary) — \(info.sizeMB) Mo").font(.caption).foregroundStyle(.secondary)
                if let progress = models.downloads[info.id] {
                    ProgressView(value: progress).controlSize(.small)
                    DownloadStallHint(models: models, modelID: info.id)
                }
            }
            Spacer()

            if models.downloads[info.id] != nil {
                Button("Annuler") { models.cancelDownload(info.id) }
            } else if installed {
                if !selected {
                    Button("Utiliser") { app.settings.selectedModelID = info.id }
                }
                Button(role: .destructive) {
                    models.delete(info.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Supprimer du disque")
            } else {
                Button("Télécharger") { models.download(info.id) }
            }
        }
    }
}

// MARK: - Historique

private struct HistorySettings: View {
    let app: AppModel
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Conservation") {
                Picker("Supprimer automatiquement après", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Conserver aussi l'audio des dictées", isOn: $settings.keepAudio)
                Text("L'audio permet de réécouter une dictée. Environ 4 Ko par seconde, stocké uniquement sur ce Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Ouvrir l'historique…") { app.windows.show(.history) }
                Button("Effacer tout l'historique…", role: .destructive) { confirmClear = true }
                    .disabled(app.controller.history == nil)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Effacer tout l'historique ?", isPresented: $confirmClear) {
            Button("Tout effacer", role: .destructive) { try? app.controller.history?.deleteAll() }
        } message: {
            Text("Les textes et les fichiers audio seront supprimés définitivement.")
        }
    }
}

// MARK: - À propos

private struct AboutView: View {
    let app: AppModel

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Micro", value: app.permissions.microphone == .granted ? "Autorisé" : "Non autorisé")
                LabeledContent("Accessibilité", value: app.permissions.accessibility ? "Autorisée" : "Non autorisée")
                Button("Assistant d'autorisations…") { app.windows.show(.onboarding) }
            }
            UpdatesSection(app: app)

            Section("Confidentialité") {
                Text("Inky fonctionne entièrement sur ton Mac. Aucun audio ni texte n'est envoyé sur Internet, et l'app ne collecte aucune statistique. Accès réseau : le téléchargement des modèles depuis Hugging Face (quand tu le demandes) et, si l'option est active, la vérification des mises à jour sur GitHub, sans aucune donnée personnelle.")
                    .font(.callout)
                Button("Afficher les données dans le Finder") {
                    _ = try? AppPaths.ensureExists(AppPaths.applicationSupport)
                    NSWorkspace.shared.open(AppPaths.applicationSupport)
                }
            }
            Section {
                Link("Code source (licence MIT)", destination: URL(string: "https://github.com/ByteOneDev/Inky")!)
            }
        }
        .formStyle(.grouped)
    }
}

/// Message affiché si un téléchargement ne progresse plus.
/// `TimelineView` redessine la vue toutes les 5 s pour réévaluer la condition.
struct DownloadStallHint: View {
    let models: ModelManager
    let modelID: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if models.isStalled(modelID, now: context.date) {
                Text("Le téléchargement semble bloqué. Annule puis relance : il reprendra où il en était.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Mises à jour

private struct UpdatesSection: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        let updates = app.updates
        Section("Mises à jour") {
            LabeledContent("Version installée", value: updates.currentVersion.description)
            Toggle("Vérifier automatiquement (au lancement, puis chaque jour)", isOn: $settings.autoCheckUpdates)
            Toggle("Installer automatiquement les nouvelles versions", isOn: $settings.autoInstallUpdates)
                .disabled(!settings.autoCheckUpdates)

            switch updates.state {
            case .idle:
                EmptyView()
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Vérification…") }
            case .upToDate:
                Label("Inky est à jour.", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .available(let update):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Version \(update.version.description) disponible", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    if !update.notes.isEmpty {
                        Text(update.notes).font(.caption).foregroundStyle(.secondary).lineLimit(6)
                    }
                    HStack {
                        Button("Installer et redémarrer") { Task { await updates.install(update) } }
                            .disabled(!updates.canInstall)
                        Link("Voir sur GitHub", destination: update.pageURL)
                    }
                    if !updates.canInstall {
                        Text("Build de développement : installe depuis la release.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .downloading(let update):
                HStack { ProgressView().controlSize(.small); Text("Téléchargement et vérification de \(update.version.description)…") }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }

            Button("Rechercher maintenant") { Task { await updates.check(userInitiated: true) } }
                .disabled(updates.state == .checking)
        }
    }
}

// MARK: - Dictionnaire

private struct DictionarySettings: View {
    let vocabulary: VocabularyStore
    @State private var newWord = ""

    var body: some View {
        @Bindable var vocabulary = vocabulary
        Form {
            Section {
                HStack {
                    TextField("Ajouter un mot (ex. Docker, Kubernetes, Inky)", text: $newWord)
                        .onSubmit(addWord)
                    Button("Ajouter", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !vocabulary.words.isEmpty {
                    FlowWords(words: vocabulary.words) { word in vocabulary.words.removeAll { $0 == word } }
                }
                Toggle("Donner ces mots au modèle comme amorce", isOn: $vocabulary.useWordsAsPrompt)
            } header: {
                Text("Mots et noms propres")
            } footer: {
                Text("L'amorce aide Whisper à bien orthographier ces mots, mais peut ralentir un peu la transcription. Si un mot reste mal écrit, ajoute une correction ci-dessous.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            RuleSection(
                title: "Corrections automatiques",
                footer: "Remplace ce que Whisper écrit par la bonne orthographe, en mots entiers, sans tenir compte des majuscules.",
                triggerLabel: "Whisper écrit…", replacementLabel: "Remplacer par…",
                kind: .correction, vocabulary: vocabulary
            )
            RuleSection(
                title: "Snippets",
                footer: "Prononce la phrase déclencheuse : Inky insère le texte complet (adresse, signature, lien…).",
                triggerLabel: "Quand je dis…", replacementLabel: "Insérer…",
                kind: .snippet, vocabulary: vocabulary
            )
        }
        .formStyle(.grouped)
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !vocabulary.words.contains(word) else { return }
        vocabulary.words.append(word)
        newWord = ""
    }
}

/// Mots du dictionnaire affichés en « jetons » supprimables.
private struct FlowWords: View {
    let words: [String]
    let onDelete: (String) -> Void

    var body: some View {
        // Grille adaptative : autant de colonnes que la largeur le permet.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 4) {
                    Text(word).lineLimit(1)
                    Button { onDelete(word) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            }
        }
    }
}

private struct RuleSection: View {
    let title: String
    let footer: String
    let triggerLabel: String
    let replacementLabel: String
    let kind: ReplacementRule.Kind
    let vocabulary: VocabularyStore

    var body: some View {
        @Bindable var vocabulary = vocabulary
        Section {
            ForEach($vocabulary.rules) { $rule in
                if rule.kind == kind {
                    HStack(alignment: .top) {
                        Toggle("", isOn: $rule.isEnabled).labelsHidden()
                        TextField(triggerLabel, text: $rule.trigger)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 3)
                        TextField(replacementLabel, text: $rule.replacement, axis: .vertical)
                            .lineLimit(1...4)
                        Button { vocabulary.remove(ruleID: rule.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button("Ajouter") { vocabulary.addRule(kind: kind) }
        } header: {
            Text(title)
        } footer: {
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mise en forme

private struct FormattingSettings: View {
    let settings: AppSettings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Supprimer les hésitations (« euh », « hum »…)", isOn: $settings.formatting.removeFillers)
                Toggle("Auto-corrections orales (« 14 h, non plutôt 15 h » → « 15 h »)", isOn: $settings.formatting.selfCorrections)
                Toggle("Commandes vocales (« à la ligne », « point d'interrogation »…)", isOn: $settings.formatting.voiceCommands)
                Toggle("Listes numérotées (« premièrement… deuxièmement… »)", isOn: $settings.formatting.numberedLists)
            } header: {
                Text("Nettoyage et mise en forme")
            } footer: {
                Text("Marqueurs de correction reconnus : « non plutôt », « ou plutôt », « je veux dire », « pardon », « enfin non », « no wait », « I mean ».")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Style messagerie : pas de point final (Messages, Slack, Discord, WhatsApp…)", isOn: $settings.formatting.casualStyleInMessaging)
                Toggle("Espacement intelligent (ajoute une espace si tu dictes juste après un mot)", isOn: $settings.smartSpacing)
            } header: {
                Text("Adaptation à l'app")
            } footer: {
                Text("L'espacement intelligent lit le caractère avant le curseur via l'Accessibilité ; certaines apps ne le permettent pas.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Commandes vocales disponibles") {
                Text("« à la ligne » · « nouveau paragraphe » · « point à la ligne » · « point d'interrogation » · « point d'exclamation » · « point-virgule » · « ouvrez / fermez les guillemets » · « ouvrez / fermez la parenthèse »")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
