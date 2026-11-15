import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Apparence de la pastille, au choix dans les réglages.
enum OverlayStyle: String, Codable, CaseIterable, Identifiable {
    /// Capsule noire, discrète, en bas de l'écran (par défaut).
    case capsule
    /// Petit magnétoscope à cassette rangé contre le bord de l'écran : il ne
    /// dépasse que d'une languette, et sort quand on dicte ou qu'on le survole.
    case cassette
    /// Petite radio (grille de haut-parleur + écran), rangée contre le bord, en
    /// plusieurs finitions.
    case radio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .capsule: "Capsule"
        case .cassette: "Magnétoscope"
        case .radio: "Radio"
        }
    }

    /// Rangé contre le bord de l'écran (et non posé à une position libre).
    var isDocked: Bool { self != .capsule }
}

/// Bord de l'écran contre lequel le magnétoscope est rangé.
enum DockEdge: Equatable { case left, right }

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
    var style: OverlayStyle = .capsule
    var finish: RadioFinish = .graphite
    var dockEdge: DockEdge = .right
    var showsTimer = true
    /// Raccourci affiché quand on survole la pastille au repos.
    var hint = ""
    /// Texte court du raccourci (« ⌃⌘ ») pour le magnétoscope.
    var shortcutLabel = ""
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
    private var hoverTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Écran où la pastille est affichée (pour calculer les cadres de survol).
    private var currentScreen: NSScreen?

    /// Marge par rapport aux bords de l'écran (la capsule ; le magnétoscope est collé au bord).
    private let margin: CGFloat = 14

    /// Taille de la fenêtre pour chaque état et chaque style.
    static func size(for phase: OverlayModel.Phase, style: OverlayStyle, hovering: Bool, showsTimer: Bool) -> CGSize {
        switch style {
        case .capsule:
            // La capsule est dessinée 2 pt à l'intérieur de la fenêtre.
            switch phase {
            case .idle: return hovering ? CGSize(width: 300, height: 36) : CGSize(width: 56, height: 20)
            case .preparing: return CGSize(width: 150, height: 44)
            case .recording(let handsFree, _): return CGSize(width: (handsFree ? 204 : 164) + (showsTimer ? 34 : 0), height: 44)
            case .transcribing: return CGSize(width: 92, height: 44)
            case .rewriting: return CGSize(width: 260, height: 44)
            case .message: return CGSize(width: 350, height: 52)
            }
        case .cassette:
            switch phase {
            case .idle: return hovering ? CassetteMetrics.full : CassetteMetrics.tab
            case .message: return CGSize(width: 320, height: 66)
            default: return CassetteMetrics.full
            }
        case .radio:
            switch phase {
            case .idle: return hovering ? RadioMetrics.full : RadioMetrics.tab
            case .message: return CGSize(width: 320, height: 70)
            default: return RadioMetrics.full
            }
        }
    }

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
        model.dockEdge = [.topLeft, .left, .bottomLeft].contains(position) ? .left : .right
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
            updateHoverTracking()
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
        updateHoverTracking()
    }

    private func reposition() {
        guard let panel else { return }
        let screen = FrontWindowLocator.screenOfFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens[0]
        currentScreen = screen
        let frame = frame(hovering: model.isHovering, on: screen)
        guard panel.frame != frame else { return }
        // Petite animation quand la pastille change de taille sur le même écran
        // (le magnétoscope « glisse » hors du bord).
        if panel.isVisible, panel.frame.intersects(screen.frame) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = model.style.isDocked ? 0.22 : 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Cadre de la fenêtre pour la phase courante.
    private func frame(hovering: Bool, on screen: NSScreen) -> CGRect {
        let size = Self.size(for: model.phase, style: model.style, hovering: hovering, showsTimer: model.showsTimer)
        let origin = model.style.isDocked
            ? dockedOrigin(size: size, on: screen)
            : origin(for: position, size: size, on: screen)
        return CGRect(origin: origin, size: size)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 56, height: 20)),
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
        panel.contentView = ClickThroughHostingView(rootView: OverlayView(model: model))
        return panel
    }

    // MARK: - Survol

    /// Survol de la pastille au repos : elle s'agrandit pour afficher l'aide.
    ///
    /// Pourquoi interroger la position de la souris (10 fois par seconde) au
    /// lieu des « zones de suivi » d'AppKit ? Parce que la fenêtre change de
    /// taille au survol : pendant l'animation, AppKit envoyait « sortie » puis
    /// « entrée » en boucle, et la pastille clignotait. Ici on compare la souris
    /// à des cadres **fixes**, avec une hystérésis : on s'agrandit quand la
    /// souris touche la petite pastille, on ne rétrécit que lorsqu'elle quitte
    /// la grande. Aucune oscillation possible.
    private func updateHoverTracking() {
        let needed = panel?.isVisible == true && model.phase == .idle
        if needed, hoverTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkHover() }
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        } else if !needed {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    private func checkHover() {
        guard model.phase == .idle, let screen = currentScreen else { return }
        let mouse = NSEvent.mouseLocation
        let hovering: Bool
        if model.isHovering {
            hovering = frame(hovering: true, on: screen).insetBy(dx: -6, dy: -6).contains(mouse)
        } else {
            hovering = frame(hovering: false, on: screen).insetBy(dx: -2, dy: -2).contains(mouse)
        }
        guard hovering != model.isHovering else { return }
        model.isHovering = hovering
        reposition()
    }

    // MARK: - Position

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

    /// Le magnétoscope et la radio sont collés au bord gauche ou droit de l'écran. La
    /// position choisie donne le bord (gauche/droite) et la hauteur (haut,
    /// milieu, bas) ; « En haut » et « En bas » (centre) vont à droite.
    private func dockedOrigin(size: CGSize, on screen: NSScreen) -> CGPoint {
        let f = screen.visibleFrame
        let x = model.dockEdge == .left ? f.minX : f.maxX - size.width
        // On aligne le centre vertical du magnétoscope, pour qu'il sorte de sa languette.
        let anchorY: CGFloat = switch position {
        case .topLeft, .top, .topRight: f.maxY - 120
        case .left, .right: f.midY
        case .bottomLeft, .bottom, .bottomRight: f.minY + 140
        }
        return CGPoint(x: x, y: anchorY - size.height / 2)
    }
}

/// Vue hôte qui accepte le « premier clic » : sans ça, le premier clic sur une
/// fenêtre d'une app inactive sert seulement à… l'activer.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
