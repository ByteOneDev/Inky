import Carbon.HIToolbox
import Foundation

/// Correspondance entre touches physiques et caractères, selon la disposition
/// clavier active (AZERTY, QWERTY, BÉPO, Dvorak…).
///
/// Pourquoi c'est utile : pour simuler ⌘V, on envoie un *code de touche
/// physique*. Sur QWERTY et AZERTY, « v » est au même endroit (code 9). Mais
/// sur BÉPO ou Dvorak, non : envoyer le code 9 produirait ⌘ + une autre lettre.
/// On demande donc au système quelle touche produit « v » avec ⌘ enfoncé.
public enum KeyboardLayout {
    /// Code de touche de repli : position du V sur un clavier QWERTY/AZERTY.
    static let fallbackVKeyCode: CGKeyCode = 9

    /// Code de la touche qui produit `character` quand ⌘ est enfoncé.
    public static func keyCode(for character: Character) -> CGKeyCode {
        let target = String(character).lowercased()
        for code in 0..<128 {
            if self.character(for: UInt16(code), withCommand: true)?.lowercased() == target {
                return CGKeyCode(code)
            }
        }
        return fallbackVKeyCode
    }

    /// Caractère produit par une touche physique dans la disposition active.
    public static func character(for keyCode: UInt16, withCommand: Bool = false) -> String? {
        // TIS = Text Input Sources : l'API (ancienne, en C) qui décrit les claviers.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        // L'état des modificateurs attendu par UCKeyTranslate est décalé de 8 bits.
        let modifierState: UInt32 = withCommand ? UInt32(cmdKey >> 8) : 0

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
