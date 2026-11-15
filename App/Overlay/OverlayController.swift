import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Ce que la pastille affiche.
@MainActor
@Observable
final class OverlayModel {
    enum Phase: Equatable {
        /// Au repos : petite pastille discrète (si « toujours visible » est activé).
        case idle
        /// Raccourci pressé, le micro démarre : « Attends… ». Parler maintenant
        /// risquerait de couper la première syllabe.
        case preparing
        /// Le micro enregistre vraiment : forme d'onde + chronomètre.
        case recording(handsFree: Bool, startedAt: Date)
        case transcribing
        /// Un modèle de prompt est appliqué par l'IA (nom du modèle).
        case rewriting(String)
        case message(String, isError: Bool)

        var isCompact: Bool { self == .idle }
    }

    var phase: Phase = .idle
    var showsTimer = true
    /// Raccourci affiché dans l'infobulle de la pastille au repos.
    var hint = ""
    /// La souris survole la pastille au repos : on affiche l'aide.
    var isHovering = false
    /// Historique glissant des niveaux sonores (0…1), un par barre.
    var levels: [Float] = Array(repeating: 0, count: OverlayModel.barCount)
    /// Clic sur la pastille (au repos : démarrer en mains libres ; en cours : arrêter).
    var onClick: (() -> Void)?
    /// Bouton ✕ de la pastille mains libres.
    var onCancel: (() -> Void)?

    static let barCount = 16

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
///   notre ⌘V collerait le texte… dans la pastille elle-même ! On peut quand
///   même cliquer dessus : le clic n'active pas Inky.
/// - **sur tous les Spaces et par-dessus les apps en plein écran**
///   (`.canJoinAllSpaces` + `.fullScreenAuxiliary`, niveau « barre d'état ») ;
/// - il suit l'écran de la fenêtre active (plusieurs écrans).
@MainActor
final class OverlayController {
    let model = OverlayModel()

    /// Réglages lus à chaque affichage (fournis par le contrôleur).
    var position: OverlayPosition = .bottom
    var showsWhileDictating = true
    var alwaysVisible = true
    var isEnabled = true

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    static let compactSize = CGSize(width: 44, height: 13)

    /// Taille de la fenêtre pour chaque état (la capsule est dessinée 2 pt à l'intérieur).
    static func size(for phase: OverlayModel.Phase, hovering: Bool, showsTimer: Bool) -> CGSize {
        switch phase {
        case .idle: hovering ? CGSize(width: 290, height: 30) : compactSize
        case .preparing: CGSize(width: 140, height: 36)
        case .recording(let handsFree, _): CGSize(width: (handsFree ? 190 : 150) + (showsTimer ? 34 : 0), height: 36)
        case .transcribing: CGSize(width: 84, height: 36)
        case .rewriting: CGSize(width: 250, height: 36)
        case .message: CGSize(width: 340, height: 46)
        }
    }
    /// Marge par rapport aux bords de l'écran.
    private let margin: CGFloat = 14

    init() {
        // Repositionner quand l'utilisateur change d'app (donc peut-être d'écran)
        // ou quand la configuration des écrans change.
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
    }

    /// Affiche une phase (ou cache la pastille selon les réglages).
    func show(_ phase: OverlayModel.Phase) {
        hideTask?.cancel()
        if phase == .preparing { model.resetLevels() }
        if phase != .idle { model.isHovering = false }
        model.phase = phase
        refresh()
    }

    /// Affiche un message, puis revient à l'état de repos.
    func flash(_ text: String, isError: Bool = false, duration: Duration = .seconds(2.5)) {
        show(.message(text, isError: isError))
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.show(.idle)
        }
    }

    /// Retour au repos (pastille compacte ou rien).
    func hide() { show(.idle) }

    /// Applique les réglages courants : visible ou non, taille, position.
    func refresh() {
        let phase = model.phase
        let visible: Bool
        if !isEnabled {
            // Inky désactivé : seuls les messages (ex. « Inky est en pause ») passent.
            if case .message = phase { visible = true } else { visible = false }
        } else if phase.isCompact {
            visible = alwaysVisible
        } else if case .message = phase {
            visible = true // les erreurs doivent rester visibles même si la pastille est masquée
        } else {
            visible = showsWhileDictating
        }

        guard visible else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Clics utiles seulement au repos et pendant l'enregistrement.
        switch phase {
        case .idle, .recording, .preparing: panel.ignoresMouseEvents = false
        default: panel.ignoresMouseEvents = true
        }
        reposition()
        panel.orderFrontRegardless() // afficher SANS activer l'app
    }

    private func reposition() {
        guard let panel else { return }
        let size = Self.size(for: model.phase, hovering: model.isHovering, showsTimer: model.showsTimer)
        let screen = FrontWindowLocator.screenOfFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = CGRect(origin: origin(for: position, size: size, on: screen), size: size)
        guard panel.frame != frame else { return }
        // Petite animation quand la pastille change de taille sur le même écran.
        if panel.isVisible, panel.frame.intersects(screen.frame) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar                 // au-dessus des fenêtres et du plein écran
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                  // l'ombre est dessinée par SwiftUI
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        let host = ClickThroughHostingView(rootView: OverlayView(model: model))
        host.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }
        panel.contentView = host
        return panel
    }

    /// Survol de la pastille au repos : elle s'agrandit pour afficher l'aide.
    private func hoverChanged(_ hovering: Bool) {
        let hovering = hovering && model.phase == .idle
        guard model.isHovering != hovering else { return }
        model.isHovering = hovering
        reposition()
    }

    /// Calcule le coin bas-gauche de la pastille. En Cocoa, l'origine (0, 0) est
    /// en **bas** à gauche de l'écran principal, et `y` monte.
    /// `visibleFrame` exclut la barre de menus et le Dock.
    private func origin(for position: OverlayPosition, size: CGSize, on screen: NSScreen) -> CGPoint {
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

/// Vue hôte qui accepte le « premier clic » : sans ça, le premier clic sur une
/// fenêtre d'une app inactive sert seulement à… l'activer.
///
/// Elle suit aussi le survol de la souris avec une zone de suivi « toujours
/// active » : la pastille appartient à une app qui n'est jamais au premier plan.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // On ne retire que notre zone : SwiftUI a les siennes.
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
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
