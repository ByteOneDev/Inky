import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Ce que la pastille affiche.
@MainActor
@Observable
final class OverlayModel {
    enum Phase: Equatable {
        case recording(handsFree: Bool)
        case transcribing
        case message(String, isError: Bool)
    }

    var phase: Phase = .transcribing
    /// Historique glissant des niveaux sonores (0…1), un par barre de la forme d'onde.
    var levels: [Float] = Array(repeating: 0, count: OverlayModel.barCount)

    static let barCount = 24

    func push(level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

/// Fenêtre flottante qui affiche la pastille.
///
/// C'est un `NSPanel` très particulier :
/// - **non activant** : il ne prend jamais le focus clavier. Indispensable, sinon
///   notre ⌘V collerait le texte… dans la pastille elle-même !
/// - **sur tous les Spaces et au-dessus des apps en plein écran**
///   (`.canJoinAllSpaces` + `.fullScreenAuxiliary`) ;
/// - **transparent aux clics** (`ignoresMouseEvents`) : il ne gêne pas.
@MainActor
final class OverlayController {
    let model = OverlayModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private let size = CGSize(width: 220, height: 48)
    /// Marge par rapport aux bords de l'écran.
    private let margin: CGFloat = 24

    func show(_ phase: OverlayModel.Phase, position: OverlayPosition) {
        hideTask?.cancel()
        if case .recording = phase, model.phase != phase { model.resetLevels() }
        model.phase = phase

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = FrontWindowLocator.screenOfFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrameOrigin(origin(for: position, on: screen))
        panel.orderFrontRegardless() // afficher SANS activer l'app
    }

    /// Affiche un message puis cache la pastille après un délai.
    func flash(_ text: String, isError: Bool = false, position: OverlayPosition, duration: Duration = .seconds(2.5)) {
        show(.message(text, isError: isError), position: position)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar                 // au-dessus des fenêtres normales
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                  // l'ombre est dessinée par SwiftUI
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    /// Calcule le coin bas-gauche de la pastille. Attention : en Cocoa, l'origine
    /// (0, 0) est en **bas** à gauche de l'écran principal, et `y` monte.
    /// `visibleFrame` exclut la barre de menus et le Dock.
    private func origin(for position: OverlayPosition, on screen: NSScreen) -> CGPoint {
        let f = screen.visibleFrame
        let left = f.minX + margin
        let centerX = f.midX - size.width / 2
        let right = f.maxX - size.width - margin
        let bottom = f.minY + margin
        let centerY = f.midY - size.height / 2
        let top = f.maxY - size.height - margin

        switch position {
        case .topLeft: return CGPoint(x: left, y: top)
        case .top: return CGPoint(x: centerX, y: top)
        case .topRight: return CGPoint(x: right, y: top)
        case .left: return CGPoint(x: left, y: centerY)
        case .right: return CGPoint(x: right, y: centerY)
        case .bottomLeft: return CGPoint(x: left, y: bottom)
        case .bottom: return CGPoint(x: centerX, y: bottom)
        case .bottomRight: return CGPoint(x: right, y: bottom)
        }
    }
}

/// Trouve l'écran qui contient la fenêtre active de l'app au premier plan.
///
/// On interroge l'API d'Accessibilité (AX) : elle donne la position et la taille
/// de la fenêtre qui a le focus, dans un repère dont l'origine est en **haut** à
/// gauche de l'écran principal (l'inverse de Cocoa) : il faut convertir.
enum FrontWindowLocator {
    @MainActor
    static func screenOfFrontmostWindow() -> NSScreen? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              let frame = focusedWindowFrame(pid: app.processIdentifier),
              let primary = NSScreen.screens.first
        else { return screenWithMouse() }

        // Conversion repère AX (haut-gauche) → repère Cocoa (bas-gauche).
        let cocoaFrame = CGRect(
            x: frame.minX,
            y: primary.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        // L'écran qui recouvre la plus grande partie de la fenêtre.
        let best = NSScreen.screens.max { a, b in
            area(a.frame.intersection(cocoaFrame)) < area(b.frame.intersection(cocoaFrame))
        }
        if let best, area(best.frame.intersection(cocoaFrame)) > 0 { return best }
        return screenWithMouse()
    }

    @MainActor
    static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return nil }
        let window = windowRef as! AXUIElement

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
