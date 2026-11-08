import Foundation

/// Un événement clavier, simplifié et indépendant de CoreGraphics.
/// (Garder ce type « pur » permet de tester toute la logique sans clavier.)
public enum HotkeyEvent: Equatable, Sendable {
    /// Les modificateurs enfoncés ont changé. `modifiers` = l'état **après** changement.
    case flagsChanged(modifiers: ModifierSet, timestamp: TimeInterval)
    case keyDown(keyCode: UInt16, modifiers: ModifierSet, isRepeat: Bool, timestamp: TimeInterval)
    case keyUp(keyCode: UInt16, modifiers: ModifierSet, timestamp: TimeInterval)
}

/// Ce que la machine à états demande à l'app de faire.
public enum HotkeyAction: Equatable, Sendable {
    /// Le raccourci push-to-talk vient d'être enfoncé : commencer à enregistrer.
    case pushToTalkBegan
    /// Le raccourci push-to-talk est relâché : arrêter et transcrire.
    case pushToTalkEnded
    /// Le raccourci mains libres a été « tapé » : démarrer ou arrêter.
    case handsFreeToggled
    /// Une autre touche a été pressée pendant le push-to-talk (ex. ⌃⌘Q) :
    /// annuler l'enregistrement push-to-talk sans transcrire.
    case pushToTalkCancelled
    /// ⎋ : annuler l'enregistrement en cours, quel que soit son mode.
    case cancel
}

/// Réponse à un événement : une action éventuelle, et faut-il « avaler »
/// l'événement (l'empêcher d'arriver à l'app au premier plan) ?
public struct HotkeyResponse: Equatable, Sendable {
    public var action: HotkeyAction?
    public var swallow: Bool

    public static let passThrough = HotkeyResponse(action: nil, swallow: false)
}

/// Le cerveau des raccourcis. Logique **pure** : aucun accès au système, donc
/// entièrement testable (voir `HotkeyStateMachineTests`).
///
/// Deux raccourcis :
/// - **push-to-talk** (défaut ⌃⌘) : enregistrer *tant que* c'est maintenu ;
/// - **mains libres** (défaut ⌃⌥) : un appui-relâché démarre, un autre arrête.
///
/// Subtilité des raccourcis « modificateurs seuls » : ⌃⌘ est aussi le début de
/// ⌃⌘Q (verrouiller l'écran). On démarre donc l'enregistrement dès ⌃⌘, mais si
/// une autre touche est pressée pendant ce temps, on **annule** et on laisse la
/// touche passer : l'utilisateur voulait un raccourci, pas dicter.
public struct HotkeyStateMachine: Sendable {
    public var pushToTalk: Shortcut
    public var handsFree: Shortcut

    /// Quand vrai, ⎋ annule l'enregistrement (et ⎋ est avalé).
    /// Le contrôleur l'active pendant qu'il enregistre.
    public var escapeCancels = false

    /// Durée maximale d'un « tap » mains libres en modificateurs seuls.
    /// Au-delà, on considère que l'utilisateur tenait ⌃⌥ pour autre chose
    /// (par ex. ⌃⌥ + clic dans une app) et on ne déclenche rien.
    public var maxTapDuration: TimeInterval = 1.0

    // État interne
    private(set) var pushToTalkActive = false
    /// Mains libres « armé » : ⌃⌥ a été pressé seul, on attend le relâchement.
    private var handsFreeArmedAt: TimeInterval?
    /// Codes de touches dont on doit aussi avaler le keyUp (parce qu'on a avalé le keyDown).
    private var swallowedKeys: Set<UInt16> = []

    static let escapeKeyCode: UInt16 = 0x35

    public init(pushToTalk: Shortcut = .defaultPushToTalk, handsFree: Shortcut = .defaultHandsFree) {
        self.pushToTalk = pushToTalk
        self.handsFree = handsFree
    }

    /// Remet l'état à zéro (par ex. après un changement de raccourci).
    public mutating func reset() {
        pushToTalkActive = false
        handsFreeArmedAt = nil
        swallowedKeys.removeAll()
    }

    public mutating func handle(_ event: HotkeyEvent) -> HotkeyResponse {
        switch event {
        case let .flagsChanged(modifiers, timestamp):
            return handleFlags(modifiers, timestamp: timestamp)
        case let .keyDown(keyCode, modifiers, isRepeat, _):
            return handleKeyDown(keyCode, modifiers: modifiers, isRepeat: isRepeat)
        case let .keyUp(keyCode, _, _):
            return handleKeyUp(keyCode)
        }
    }

    // MARK: - Modificateurs

    private mutating func handleFlags(_ mods: ModifierSet, timestamp: TimeInterval) -> HotkeyResponse {
        // — Push-to-talk en modificateurs seuls —
        if pushToTalk.isModifierOnly {
            if !pushToTalkActive && mods == pushToTalk.modifiers {
                pushToTalkActive = true
                handsFreeArmedAt = nil
                return HotkeyResponse(action: .pushToTalkBegan, swallow: false)
            }
            if pushToTalkActive && mods != pushToTalk.modifiers {
                // Un modificateur a été relâché (ou ajouté) : fin de la prise de parole.
                pushToTalkActive = false
                return HotkeyResponse(action: .pushToTalkEnded, swallow: false)
            }
        }

        // — Mains libres en modificateurs seuls : déclenché au RELÂCHEMENT —
        if handsFree.isModifierOnly {
            if mods == handsFree.modifiers {
                if handsFreeArmedAt == nil { handsFreeArmedAt = timestamp }
            } else if let armedAt = handsFreeArmedAt {
                if mods.isEmpty {
                    // Tout est relâché : c'était un « tap » s'il a été assez bref.
                    handsFreeArmedAt = nil
                    if timestamp - armedAt <= maxTapDuration {
                        return HotkeyResponse(action: .handsFreeToggled, swallow: false)
                    }
                } else if !mods.isSubset(of: handsFree.modifiers) {
                    // Un modificateur étranger a été ajouté (ex. ⌃⌥⌘) : ce n'est plus notre raccourci.
                    handsFreeArmedAt = nil
                }
                // Sinon : relâchement partiel (⌃ lâché avant ⌥), on reste armé.
            }
        }
        return .passThrough
    }

    // MARK: - Touches

    private mutating func handleKeyDown(_ keyCode: UInt16, modifiers mods: ModifierSet, isRepeat: Bool) -> HotkeyResponse {
        // ⎋ pendant un enregistrement : annuler.
        if escapeCancels && keyCode == Self.escapeKeyCode {
            pushToTalkActive = false
            handsFreeArmedAt = nil
            swallowedKeys.insert(keyCode)
            return HotkeyResponse(action: .cancel, swallow: true)
        }

        // — Raccourcis avec touche —
        if let key = pushToTalk.keyCode, key == keyCode {
            if pushToTalkActive { return HotkeyResponse(action: nil, swallow: true) } // répétition auto
            if mods == pushToTalk.modifiers && !isRepeat {
                pushToTalkActive = true
                swallowedKeys.insert(keyCode)
                return HotkeyResponse(action: .pushToTalkBegan, swallow: true)
            }
        }
        if let key = handsFree.keyCode, key == keyCode, mods == handsFree.modifiers {
            swallowedKeys.insert(keyCode)
            return HotkeyResponse(action: isRepeat ? nil : .handsFreeToggled, swallow: true)
        }

        // — Une autre touche pendant un raccourci « modificateurs seuls » —
        // L'utilisateur fait en réalité ⌃⌘Q, ⌃⌥→… : on annule et on laisse passer.
        handsFreeArmedAt = nil
        if pushToTalkActive && pushToTalk.isModifierOnly {
            pushToTalkActive = false
            return HotkeyResponse(action: .pushToTalkCancelled, swallow: false)
        }
        return .passThrough
    }

    private mutating func handleKeyUp(_ keyCode: UInt16) -> HotkeyResponse {
        if let key = pushToTalk.keyCode, key == keyCode, pushToTalkActive {
            pushToTalkActive = false
            swallowedKeys.remove(keyCode)
            return HotkeyResponse(action: .pushToTalkEnded, swallow: true)
        }
        if swallowedKeys.remove(keyCode) != nil {
            return HotkeyResponse(action: nil, swallow: true)
        }
        return .passThrough
    }
}
