import Foundation

/// Auto-corrections orales : « rendez-vous à 14 h, non plutôt 15 h »
/// devient « rendez-vous à 15 h ».
///
/// Principe (heuristique simple, sans IA) : quand on repère un marqueur de
/// correction (« non plutôt », « je veux dire », « no wait »…), la correction
/// qui suit compte N mots ; on supprime les N mots qui précèdent le marqueur et
/// on met la correction à leur place.
///
///     rendez-vous à 14 h, non plutôt 15 h
///                   ^^^^ ─────────── ^^^^   2 mots remplacés par 2 mots
///
/// Limites assumées : la correction doit être courte (6 mots max) et finir la
/// phrase. Pour des reformulations plus libres, il faudra le LLM de la v0.2.
public enum SelfCorrection {
    /// Marqueurs reconnus (en minuscules). On évite « non » tout seul : trop
    /// fréquent dans une phrase normale (« Non, je reste »).
    static let markers = [
        "non plutôt", "ou plutôt", "non pardon", "enfin non", "non attends",
        "je veux dire", "pardon",
        "no wait", "i mean", "actually no", "sorry I mean",
    ]

    static let maxCorrectionWords = 6

    public static func apply(to text: String) -> String {
        // On traite phrase par phrase : une correction ne déborde pas sur la phrase d'avant.
        splitSentences(text).map(applyToSentence).joined()
    }

    private static func applyToSentence(_ sentence: String) -> String {
        let markerPattern = markers
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
            .joined(separator: "|")
        // Groupe 1 : avant le marqueur. Groupe 2 : la correction. Groupe 3 : ponctuation finale.
        let pattern = "^(.*?)[,;]?\\s*(?:\(markerPattern))\\s*[,:]?\\s+(.+?)([.!?…]*\\s*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
              let beforeRange = Range(match.range(at: 1), in: sentence),
              let correctionRange = Range(match.range(at: 2), in: sentence),
              let endRange = Range(match.range(at: 3), in: sentence)
        else { return sentence }

        let before = String(sentence[beforeRange]).trimmingCharacters(in: .whitespaces)
        let correction = String(sentence[correctionRange]).trimmingCharacters(in: .whitespaces)
        let ending = String(sentence[endRange])

        let correctionWords = correction.split(whereSeparator: \.isWhitespace)
        var beforeWords = before.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !correctionWords.isEmpty,
              correctionWords.count <= maxCorrectionWords,
              beforeWords.count >= correctionWords.count
        else { return sentence }

        beforeWords.removeLast(correctionWords.count)
        var result = (beforeWords + correctionWords.map(String.init)).joined(separator: " ")
        // Ponctuation orpheline éventuelle (« …, » avant le marqueur).
        while let last = result.last, ",;".contains(last) { result.removeLast() }
        if let first = result.first, before.first?.isUppercase == true {
            result = first.uppercased() + result.dropFirst()
        }
        return result + ending
    }

    /// Découpe en phrases en gardant la ponctuation et les espaces de fin.
    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var iterator = text.makeIterator()
        var pendingTerminator = false
        while let char = iterator.next() {
            if pendingTerminator && !".!?…".contains(char) && !char.isWhitespace {
                sentences.append(current)
                current = ""
                pendingTerminator = false
            }
            current.append(char)
            if ".!?…".contains(char) { pendingTerminator = true }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }
}
