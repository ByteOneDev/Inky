import AppKit
import SwiftUI

/// Contenu du menu de la barre de menus.
struct MenuContent: View {
    let app: AppModel

    private var controller: DictationController { app.controller }

    var body: some View {
        Text(statusText)

        if !app.permissions.allGranted {
            Button("⚠︎ Autorisations manquantes…") { app.windows.show(.onboarding) }
        }

        Text("Push-to-talk : \(app.settings.pushToTalkShortcut.displayString)   ·   Mains libres : \(app.settings.handsFreeShortcut.displayString)")

        Divider()

        if let last = controller.lastTranscript {
            Button("Copier la dernière dictée") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last, forType: .string)
            }
        }
        Button("Historique…") { app.windows.show(.history) }
            .keyboardShortcut("h")
        Button("Réglages…") { app.windows.show(.settings) }
            .keyboardShortcut(",")

        Divider()

        Button("Quitter Inky") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch controller.phase {
        case .recording: return "● Enregistrement…"
        case .transcribing: return "Transcription…"
        case .idle: break
        }
        switch controller.modelStatus {
        case .notInstalled: return "Aucun modèle installé"
        case .loading(let name): return "Chargement de \(name)…"
        case .failed: return "Erreur de chargement du modèle"
        case .ready(let name):
            return controller.hotkeysActive ? "Prêt · \(name)" : "Raccourcis inactifs (Accessibilité)"
        }
    }
}
