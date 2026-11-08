import InkyCore
import InkyInsertion
import InkyHotkeys
import InkyStorage
import InkyTranscription
import SwiftUI
import os

/// Point d'entrée de l'app.
///
/// Inky est une app « agent » (`LSUIElement` dans Info.plist) : pas d'icône dans
/// le Dock, uniquement une icône dans la barre de menus (`MenuBarExtra`).
@main
struct InkyApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: app)
        } label: {
            // L'icône change selon l'état : repos, enregistrement, transcription.
            Image(systemName: app.controller.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// La « racine de composition » : crée tous les objets une seule fois et les
/// relie entre eux. C'est le seul endroit qui connaît les implémentations
/// concrètes (WhisperKitEngine, PasteboardInserter…).
@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let permissions = PermissionsManager()
    let models = ModelManager()
    let controller: DictationController
    @ObservationIgnored private(set) lazy var windows = WindowCoordinator(app: self)

    init() {
        // Le nom des touches dans les réglages suit la disposition clavier active.
        KeyNames.characterProvider = { KeyboardLayout.character(for: $0)?.uppercased() }

        let history: HistoryStore?
        do {
            history = try HistoryStore()
        } catch {
            Logger(subsystem: "com.byteonedev.inky", category: "app").error("Historique indisponible : \(error.localizedDescription, privacy: .public)")
            history = nil
        }

        controller = DictationController(settings: settings, permissions: permissions, models: models, history: history)
        controller.start()

        // Premier lancement, ou autorisation perdue (ex. après une mise à jour
        // non signée) : on affiche l'écran d'accueil.
        let needsOnboarding = !settings.hasCompletedOnboarding || !permissions.allGranted
        if needsOnboarding {
            Task { @MainActor [weak self] in self?.windows.show(.onboarding) }
        }
    }
}

extension DictationController {
    /// Symbole SF affiché dans la barre de menus.
    var menuBarSymbol: String {
        switch phase {
        case .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .idle: hotkeysActive ? "waveform" : "waveform.slash"
        }
    }
}
