import AppKit
import SwiftUI

/// Ouvre les fenêtres de l'app (Réglages, Historique, Bienvenue).
///
/// Pourquoi de l'AppKit plutôt que des scènes SwiftUI `Window` ? Une app sans
/// Dock (`LSUIElement`) n'est jamais « active » par défaut : ses fenêtres
/// s'ouvriraient derrière les autres. Ici on contrôle explicitement l'activation
/// et on réutilise la fenêtre si elle est déjà ouverte.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    enum Kind: String {
        case settings, history, onboarding

        var title: String {
            switch self {
            case .settings: "Réglages d'Inky"
            case .history: "Historique"
            case .onboarding: "Bienvenue dans Inky"
            }
        }
    }

    private unowned let app: AppModel
    private var windows: [Kind: NSWindow] = [:]

    init(app: AppModel) {
        self.app = app
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
        case .settings: AnyView(SettingsView(app: app))
        case .history: AnyView(HistoryView(app: app))
        case .onboarding: AnyView(OnboardingView(app: app))
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = kind.title
        window.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
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
