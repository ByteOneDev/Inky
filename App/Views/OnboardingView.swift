import InkyTranscription
import SwiftUI

/// Écran d'accueil : autorisations + premier modèle.
struct OnboardingView: View {
    let app: AppModel

    private var permissions: PermissionsManager { app.permissions }
    private var models: ModelManager { app.models }
    private var settings: AppSettings { app.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bienvenue dans Inky").font(.largeTitle.bold())
                Text("Trois étapes, et tu pourras dicter partout. Tout reste sur ton Mac.")
                    .foregroundStyle(.secondary)
            }

            StepCard(
                number: 1,
                title: "Micro",
                detail: microphoneDetail,
                done: permissions.microphone == .granted,
                buttonTitle: permissions.microphone == .denied ? "Ouvrir les Réglages" : "Autoriser le micro"
            ) {
                Task { await permissions.requestMicrophone() }
            }

            StepCard(
                number: 2,
                title: "Accessibilité",
                detail: "Nécessaire pour détecter les raccourcis partout et coller le texte dans l'app active. Coche « Inky » dans la liste qui va s'ouvrir.",
                done: permissions.accessibility,
                buttonTitle: "Ouvrir les Réglages"
            ) {
                permissions.requestAccessibility()
            }

            StepCard(
                number: 3,
                title: "Modèle de transcription",
                detail: modelDetail,
                done: models.isInstalled(settings.selectedModelID),
                buttonTitle: models.downloads[settings.selectedModelID] == nil ? "Télécharger" : "Téléchargement…"
            ) {
                models.download(settings.selectedModelID)
            }
            if let progress = models.downloads[settings.selectedModelID] {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    DownloadStallHint(models: models, modelID: settings.selectedModelID)
                    if models.isStalled(settings.selectedModelID) {
                        Button("Annuler le téléchargement") { models.cancelDownload(settings.selectedModelID) }
                    }
                }
                .padding(.leading, 44)
            }
            if let error = models.lastError {
                Text(error).font(.caption).foregroundStyle(.red).padding(.leading, 44)
            }

            if permissions.accessibility == false {
                Text("Astuce : si Inky est déjà coché mais que ça ne marche pas (après une mise à jour), retire-le de la liste avec « − » puis ajoute-le à nouveau.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Push-to-talk : maintiens \(settings.pushToTalkShortcut.displayString). Mains libres : appuie sur \(settings.handsFreeShortcut.displayString).")
                    .font(.callout)
                Spacer()
                Button("Terminer") {
                    settings.hasCompletedOnboarding = true
                    app.windows.close(.onboarding)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!permissions.allGranted)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var microphoneDetail: String {
        switch permissions.microphone {
        case .denied: "L'accès a été refusé. Active « Inky » dans Réglages Système › Confidentialité et sécurité › Micro."
        default: "Pour entendre ta voix. Le micro n'est actif que pendant une dictée."
        }
    }

    private var modelDetail: String {
        let info = ModelCatalog.info(for: settings.selectedModelID) ?? ModelCatalog.recommended
        return "\(info.displayName), \(info.sizeMB) Mo, téléchargé une seule fois depuis Hugging Face. Le premier chargement peut prendre une à deux minutes (optimisation pour ta puce)."
    }
}

private struct StepCard: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 30, height: 30)
                if done {
                    Image(systemName: "checkmark").foregroundStyle(.white).bold()
                } else {
                    Text("\(number)").foregroundStyle(.white).bold()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done {
                Button(buttonTitle, action: action)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
