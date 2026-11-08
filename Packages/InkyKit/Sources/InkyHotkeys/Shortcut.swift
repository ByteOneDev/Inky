import Foundation

/// Ensemble de touches modificatrices (⌃ ⌥ ⇧ ⌘ fn).
///
/// `OptionSet` = un ensemble de bits : chaque modificateur est un bit d'un
/// entier. `[.control, .command]` vaut donc 0b1001. Comparer deux ensembles est
/// une simple comparaison d'entiers, ce qui est très rapide (important dans
/// l'event tap, qui doit répondre en quelques microsecondes).
public struct ModifierSet: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control  = ModifierSet(rawValue: 1 << 0)
    public static let option   = ModifierSet(rawValue: 1 << 1)
    public static let shift    = ModifierSet(rawValue: 1 << 2)
    public static let command  = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    /// Nombre de modificateurs dans l'ensemble.
    public var count: Int { rawValue.nonzeroBitCount }

    /// Symboles dans l'ordre standard d'Apple : fn ⌃ ⌥ ⇧ ⌘.
    public var symbols: String {
        var s = ""
        if contains(.function) { s += "fn " }
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// Un raccourci : des modificateurs, plus éventuellement une touche « normale ».
///
/// - `keyCode == nil` : raccourci « modificateurs seuls », par ex. ⌃⌘.
/// - `keyCode != nil` : combinaison classique, par ex. ⌥Espace.
///
/// Le `keyCode` est le code de la touche **physique** (indépendant de la
/// disposition AZERTY/QWERTY), tel que fourni par macOS.
public struct Shortcut: Hashable, Codable, Sendable {
    public var modifiers: ModifierSet
    public var keyCode: UInt16?

    public init(modifiers: ModifierSet, keyCode: UInt16? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public var isModifierOnly: Bool { keyCode == nil }

    /// Défauts choisis pour Inky.
    public static let defaultPushToTalk = Shortcut(modifiers: [.control, .command])
    public static let defaultHandsFree = Shortcut(modifiers: [.control, .option])

    /// Un raccourci valide doit être assez « rare » pour ne pas se déclencher
    /// par accident : au moins 2 modificateurs (ou fn) s'il n'y a pas de touche,
    /// au moins 1 modificateur sinon.
    public var isValid: Bool {
        if isModifierOnly {
            return modifiers.count >= 2 || modifiers == .function
        }
        return modifiers.count >= 1
    }

    /// Texte affichable, par ex. « ⌃⌘ » ou « ⌥ Espace ».
    public var displayString: String {
        let mods = modifiers.symbols
        guard let keyCode else { return mods }
        return mods + " " + KeyNames.name(for: keyCode)
    }
}

/// Noms lisibles des touches les plus courantes (codes de touches physiques
/// définis par Apple dans `HIToolbox/Events.h`, ex. `kVK_Space = 0x31`).
public enum KeyNames {
    public static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0x31: "Espace"
        case 0x24: "↩"
        case 0x30: "⇥"
        case 0x33: "⌫"
        case 0x35: "⎋"
        case 0x7A: "F1"
        case 0x78: "F2"
        case 0x63: "F3"
        case 0x76: "F4"
        case 0x60: "F5"
        case 0x61: "F6"
        case 0x62: "F7"
        case 0x64: "F8"
        case 0x65: "F9"
        case 0x6D: "F10"
        case 0x67: "F11"
        case 0x6F: "F12"
        case 0x7B: "←"
        case 0x7C: "→"
        case 0x7D: "↓"
        case 0x7E: "↑"
        default: KeyNames.characterProvider?(keyCode) ?? "Touche \(keyCode)"
        }
    }

    /// Permet à l'app de fournir le caractère réel de la touche selon la
    /// disposition clavier active (voir `KeyboardLayout` dans InkyInsertion).
    nonisolated(unsafe) public static var characterProvider: ((UInt16) -> String?)?
}
