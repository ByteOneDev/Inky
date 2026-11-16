import InkyAudio
import InkyCore
import InkyStorage
import InkyTranscription
import SwiftUI

// MARK: - Général

struct GeneralSettings: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        FormPage(title: "Général", subtitle: "Raccourcis, pastille et insertion du texte.") {
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
                OverlayStyleGallery(settings: settings)
                    .padding(.vertical, 4)
                Text(settings.overlayStyle.isDocked
                     ? "Rangé contre le bord de l'écran : seule une languette dépasse. Il sort quand tu le survoles ou que tu dictes. La position choisit le bord (gauche ou droite) et la hauteur."
                     : "Une capsule noire discrète, à l'endroit choisi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Survole la petite pastille pour voir le raccourci ; en mains libres, ✕ annule et ■ termine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }
}

// MARK: - Audio

struct AudioSettings: View {
    let settings: AppSettings
    let controller: DictationController
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        @Bindable var settings = settings
        FormPage(title: "Audio", subtitle: "Micro, diagnostic du démarrage et sons.") {
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
            Section {
                Toggle("Mettre en pause la musique et les vidéos pendant la dictée", isOn: $settings.pauseMediaWhileDictating)
            } header: {
                Text("Musique et vidéos")
            } footer: {
                Text("Musique, Spotify, YouTube… se mettent en pause quand tu commences à dicter et reprennent à la fin. Inky ne relance que ce qu'il a lui-même mis en pause. Avec une vidéo dans un navigateur, la reprise peut attendre quelques secondes après une dictée très courte.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { devices = AudioDevices.inputDevices() }
    }
}

// MARK: - Modèles

struct ModelSettings: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        let models = app.models
        FormPage(title: "Transcription", subtitle: "Langue de dictée et moteur de transcription, exécuté localement sur le Neural Engine.") {
            Section("Langue") {
                Picker("Langue de dictée", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Forcer le français reste efficace quand tu glisses des mots anglais. La détection automatique (Whisper seulement ; la dictée Apple utilise alors le français) se trompe plus souvent sur les phrases courtes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ModelCatalog.models) { info in
                    ModelRow(info: info, app: app)
                }
            } header: {
                Text("Moteur de transcription")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText).font(.caption)
                    if let error = models.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
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
                Text(info.isSystem ? "\(info.summary) — intégré à macOS" : "\(info.summary) — \(info.sizeMB) Mo")
                    .font(.caption).foregroundStyle(.secondary)
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
                if !info.isSystem {
                    Button(role: .destructive) {
                        models.delete(info.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Supprimer du disque")
                }
            } else {
                Button("Télécharger") { models.download(info.id) }
            }
        }
    }
}

// MARK: - À propos

struct AboutView: View {
    let app: AppModel

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        FormPage(title: "À propos", subtitle: "Version, autorisations, mises à jour et confidentialité.") {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Micro", value: app.permissions.microphone == .granted ? "Autorisé" : "Non autorisé")
                LabeledContent("Accessibilité", value: app.permissions.accessibility ? "Autorisée" : "Non autorisée")
                Button("Assistant d'autorisations…") { app.windows.show(.onboarding) }
                Button("Revoir le tutoriel…") { app.windows.show(.tutorial) }
            }
            UpdatesSection(app: app)

            Section("Confidentialité") {
                Text("Inky fonctionne entièrement sur ton Mac. Aucun audio ni texte n'est envoyé sur Internet. Les statistiques de l'accueil sont calculées et stockées uniquement sur ce Mac. Les prompts IA utilisent Apple Intelligence en local. Accès réseau : le téléchargement des modèles depuis Hugging Face (quand tu le demandes) et, si l'option est active, la vérification des mises à jour sur GitHub, sans aucune donnée personnelle.")
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
