import CoreGraphics
import Foundation
import InkyCore
import os

/// Écoute le clavier **de tout le système** grâce à un `CGEventTap`.
///
/// Un event tap est un « robinet » placé dans le flux des événements clavier de
/// la session : chaque frappe passe par notre callback, qui peut la laisser
/// passer, ou l'avaler (renvoyer `nil`).
///
/// Conditions :
/// - L'app doit avoir l'autorisation **Accessibilité**, sinon `tapCreate`
///   échoue (renvoie `nil`).
/// - Le callback doit être **très rapide** : s'il traîne, macOS désactive le tap
///   (`tapDisabledByTimeout`) pour ne pas bloquer le clavier de tout le Mac.
///   On se contente donc de passer l'événement à la machine à états et de
///   transmettre l'action ; le travail lourd se fait ailleurs, en asynchrone.
@MainActor
public final class EventTapMonitor {
    /// Appelé (sur le thread principal) quand un raccourci produit une action.
    public var onAction: ((HotkeyAction) -> Void)?

    /// La logique des raccourcis. Modifiable à chaud (changement dans les réglages).
    public var stateMachine = HotkeyStateMachine()

    /// Mettre en pause sans détruire le tap (pendant l'enregistrement d'un
    /// nouveau raccourci dans les réglages, par exemple).
    public var isPaused = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "hotkeys")

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Installe le tap. Renvoie `false` si l'autorisation Accessibilité manque.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        // Masque de bits des types d'événements qui nous intéressent.
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        // Le callback est une fonction C : il ne peut rien « capturer ».
        // On lui passe donc un pointeur vers `self` via `userInfo`.
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,       // tous les événements de la session utilisateur
            place: .headInsertEventTap,    // avant les autres taps
            options: .defaultTap,          // actif : on peut avaler des événements
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            logger.error("Impossible de créer l'event tap (autorisation Accessibilité manquante ?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        logger.info("Event tap installé")
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        stateMachine.reset()
    }

    /// Appelé par le callback C, sur le thread principal.
    /// Renvoie `true` si l'événement doit continuer son chemin, `false` pour l'avaler.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        // macOS a désactivé le tap (callback trop lent, ou saisie sécurisée) : on le réactive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("Event tap désactivé par le système, réactivation")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            stateMachine.reset()
            return true
        }

        // Nos propres ⌘V synthétiques : on ne les regarde pas.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticEvents.marker || isPaused {
            return true
        }

        guard let hotkeyEvent = Self.convert(type: type, event: event) else {
            return true
        }

        let response = stateMachine.handle(hotkeyEvent)
        if let action = response.action {
            onAction?(action)
        }
        return !response.swallow
    }

    /// Traduit un `CGEvent` en `HotkeyEvent` (notre type simplifié).
    static func convert(type: CGEventType, event: CGEvent) -> HotkeyEvent? {
        // `timestamp` est en nanosecondes depuis le démarrage du Mac.
        let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        var modifiers = modifierSet(from: event.flags)

        switch type {
        case .flagsChanged:
            return .flagsChanged(modifiers: modifiers, timestamp: timestamp)
        case .keyDown, .keyUp:
            // Les flèches et touches F portent le drapeau « fn » même sans appui
            // sur fn : on l'ignore pour les combinaisons avec touche.
            modifiers.remove(.function)
            if type == .keyDown {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                return .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, timestamp: timestamp)
            }
            return .keyUp(keyCode: keyCode, modifiers: modifiers, timestamp: timestamp)
        default:
            return nil
        }
    }

    static func modifierSet(from flags: CGEventFlags) -> ModifierSet {
        var set: ModifierSet = []
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskShift) { set.insert(.shift) }
        if flags.contains(.maskCommand) { set.insert(.command) }
        if flags.contains(.maskSecondaryFn) { set.insert(.function) }
        return set
    }
}

/// Fonction C appelée par macOS pour chaque événement clavier.
/// Le tap est attaché à la run loop principale : on est donc sur le thread
/// principal, ce que `MainActor.assumeIsolated` affirme au compilateur.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<EventTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // CGEvent n'est pas `Sendable` : on promet au compilateur qu'on reste sur ce thread.
    nonisolated(unsafe) let event = event
    let shouldPass = MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
    return shouldPass ? Unmanaged.passUnretained(event) : nil
}
