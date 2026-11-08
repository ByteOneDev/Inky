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
        Self.terminateOtherInstances()

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

extension AppModel {
    /// Une seule instance d'Inky à la fois : deux instances réagiraient toutes
    /// les deux au raccourci et colleraient le texte deux fois (et se
    /// disputeraient les téléchargements de modèles). La plus récente gagne :
    /// c'est le comportement attendu après une mise à jour ou un lancement
    /// depuis Xcode.
    static func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard !others.isEmpty else { return }
        for app in others { app.terminate() }
        // Laisser jusqu'à 2 s aux autres instances pour se fermer proprement.
        let deadline = Date().addingTimeInterval(2)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        for app in others where !app.isTerminated { app.forceTerminate() }
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
