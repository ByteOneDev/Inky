import AppKit
import SwiftUI

/// Ouvre les fenêtres de l'app : la fenêtre principale (accueil, historique,
/// réglages…), l'écran de bienvenue et le tutoriel.
///
/// Pourquoi de l'AppKit plutôt que des scènes SwiftUI `Window` ? Une app sans
/// Dock (`LSUIElement`) n'est jamais « active » par défaut : ses fenêtres
/// s'ouvriraient derrière les autres. Ici on contrôle explicitement l'activation
/// et on réutilise la fenêtre si elle est déjà ouverte.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    enum Kind: String {
        case main, onboarding, tutorial

        var title: String {
            switch self {
            case .main: "Inky"
            case .onboarding: "Bienvenue dans Inky"
            case .tutorial: "Tutoriel Inky"
            }
        }
    }

    private unowned let app: AppModel
    private var windows: [Kind: NSWindow] = [:]

    init(app: AppModel) {
        self.app = app
    }

    /// Ouvre la fenêtre principale sur une page donnée.
    func show(_ section: MainSection) {
        app.navigation.section = section
        show(.main)
    }

    func show(_ kind: Kind) {
        let window = windows[kind] ?? makeWindow(kind)
        windows[kind] = window
        if kind == .onboarding { app.permissions.startPolling() }
        // Une app agent doit s'activer explicitement pour passer devant.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    private func makeWindow(_ kind: Kind) -> NSWindow {
        let root: AnyView = switch kind {
        case .main: AnyView(MainWindowView(app: app))
        case .onboarding: AnyView(OnboardingView(app: app))
        case .tutorial: AnyView(TutorialView(app: app))
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = kind.title
        window.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        if kind == .main {
            // Barre de titre transparente : la barre latérale monte jusqu'en haut,
            // les boutons de fenêtre flottent par-dessus (style des apps modernes).
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(CGSize(width: 980, height: 680))
            window.setFrameAutosaveName("InkyMainWindow")
        }
        window.isReleasedWhenClosed = false
        // S'ouvrir sur le bureau (Space) affiché, même si l'utilisateur est dans
        // une app en plein écran, au lieu de rester sur un autre bureau.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let raw = window.identifier?.rawValue,
              let kind = Kind(rawValue: raw)
        else { return }
        windows[kind] = nil
        if kind == .onboarding { app.permissions.stopPolling() }
    }
}
