import AppKit
import SwiftUI

/// Contenu du menu de la barre de menus.
struct MenuContent: View {
    let app: AppModel

    private var controller: DictationController { app.controller }

    var body: some View {
        @Bindable var settings = app.settings

        Text(statusText)

        if !app.permissions.allGranted {
            Button("⚠︎ Autorisations manquantes…") { app.windows.show(.onboarding) }
        }

        // Interrupteur général : met Inky en pause (raccourcis et pastille).
        Toggle("Inky activé", isOn: $settings.isEnabled)

        Text("Push-to-talk : \(settings.pushToTalkShortcut.displayString)   ·   Mains libres : \(settings.handsFreeShortcut.displayString)")

        Divider()

        if let last = controller.lastTranscript {
            Button("Copier la dernière dictée") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last, forType: .string)
            }
        }
        Button("Historique…") { app.windows.show(.history) }
            .keyboardShortcut("h")

        Menu("Pastille") {
            Toggle("Toujours visible (même en plein écran)", isOn: $settings.overlayAlwaysVisible)
            Toggle("Afficher pendant la dictée", isOn: $settings.overlayEnabled)
        }

        Divider()

        if let update = app.updates.availableUpdate {
            Button("⬆︎ Installer la version \(update.version.description)…") {
                Task { await app.updates.install(update) }
            }
            .disabled(!app.updates.canInstall)
        } else {
            Button("Rechercher des mises à jour…") {
                Task { await app.updates.check(userInitiated: true) }
                app.windows.show(.settings)
            }
        }
        Button("Tutoriel…") { app.windows.show(.tutorial) }
        Button("Réglages…") { app.windows.show(.settings) }
            .keyboardShortcut(",")

        Divider()

        Button("Quitter Inky") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        if !app.settings.isEnabled { return "En pause" }
        switch controller.phase {
        case .preparing: return "Démarrage du micro…"
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
