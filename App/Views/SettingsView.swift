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
            AudioSettings(settings: app.settings)
                .tabItem { Label("Audio", systemImage: "mic") }
            ModelSettings(app: app)
                .tabItem { Label("Modèles", systemImage: "cpu") }
            HistorySettings(app: app)
                .tabItem { Label("Historique", systemImage: "clock") }
            AboutView(app: app)
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        Form {
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
                Picker("Position", selection: $settings.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { Text($0.displayName).tag($0) }
                }
                Button("Aperçu") {
                    app.controller.overlay.flash("Aperçu de la pastille", position: settings.overlayPosition)
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
            Section("Retour sonore") {
                Toggle("Jouer un son au début et à la fin de l'enregistrement", isOn: $settings.playSounds)
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
                Toggle("Supprimer les hésitations (« euh », « hum »…)", isOn: $settings.removeFillers)
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
            Section("Confidentialité") {
                Text("Inky fonctionne entièrement sur ton Mac. Aucun audio ni texte n'est envoyé sur Internet, et l'app ne collecte aucune statistique. Le seul accès réseau est le téléchargement des modèles depuis Hugging Face, quand tu le demandes.")
                    .font(.callout)
                Button("Afficher les données dans le Finder") {
                    try? AppPaths.ensureExists(AppPaths.applicationSupport)
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
