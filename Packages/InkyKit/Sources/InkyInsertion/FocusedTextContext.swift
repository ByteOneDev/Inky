import ApplicationServices
import Foundation

/// Lit le texte autour du curseur dans l'app active, via l'API d'Accessibilité.
///
/// Sert à l'**espacement intelligent** : si on dicte juste après « Bonjour »,
/// il faut insérer « ␣comment ça va », pas « comment ça va » collé au mot.
///
/// Toutes les apps n'exposent pas ces informations (Electron, terminaux,
/// certains éditeurs) : dans ce cas on renvoie `nil` et on n'ajoute rien.
public enum FocusedTextContext {
    /// Caractère situé juste avant le curseur, ou `nil` si inconnu.
    /// Renvoie `"\n"` en début de champ (rien avant le curseur).
    public static func characterBeforeCursor() -> Character? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        // Position du curseur = début de la sélection courante.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }
        if selection.location <= 0 { return "\n" }

        // Lire le seul caractère précédent (attribut « paramétré » : on passe une plage).
        var previous = CFRange(location: selection.location - 1, length: 1)
        guard let previousValue = AXValueCreate(.cfRange, &previous) else { return nil }
        var stringRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            previousValue,
            &stringRef
        )
        if status == .success, let string = stringRef as? String, let char = string.last {
            return char
        }

        // Repli : certaines apps n'ont pas l'attribut paramétré mais exposent la valeur complète.
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String
        else { return nil }
        let utf16 = Array(value.utf16)
        let index = selection.location - 1
        guard index >= 0, index < utf16.count else { return nil }
        return String(utf16CodeUnits: [utf16[index]], count: 1).first
    }

    /// Texte situé avant le curseur dans le champ actif (au plus `maxLength`
    /// caractères, les plus proches du curseur), ou `nil` si l'app ne l'expose pas.
    ///
    /// Sert aux modèles de prompts « compléter » : l'IA lit le début du mail
    /// pour en écrire la suite. Rien n'est stocké ni envoyé hors du Mac.
    public static func textBeforeCursor(maxLength: Int = 6000) -> String? {
        guard let element = focusedElement(),
              let selection = selectedRange(of: element)
        else { return nil }
        let end = max(0, selection.location)
        if end == 0 { return "" }
        let start = max(0, end - maxLength)

        var range = CFRange(location: start, length: end - start)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &stringRef) == .success,
               let string = stringRef as? String {
                return string
            }
        }
        // Repli : la valeur complète du champ, coupée au curseur.
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String
        else { return nil }
        let utf16 = Array(value.utf16)
        guard end <= utf16.count else { return nil }
        return String(utf16CodeUnits: Array(utf16[start..<end]), count: end - start)
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        return (focusedRef as! AXUIElement)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }
        return selection
    }

    /// Ajoute une espace devant `text` si le curseur suit directement un mot ou
    /// une ponctuation de fin (« Bonjour.|Comment » → « Bonjour. Comment »).
    public static func applySmartSpacing(to text: String, previous: Character?) -> String {
        guard let previous, let first = text.first else { return text }
        if previous.isWhitespace || first.isWhitespace { return text }
        // Après une ouverture, pas d'espace : « (|texte ».
        if "([{«\"'/-@#".contains(previous) { return text }
        // Le texte commence par une ponctuation qui se colle au mot précédent.
        if ",.)]}…".contains(first) { return text }
        return " " + text
    }
}
