import Foundation

/// Transforme une énumération dictée en liste numérotée.
///
/// « Il faut premièrement acheter du pain, deuxièmement du lait et
/// troisièmement des œufs. » devient :
///
///     Il faut :
///     1. Acheter du pain
///     2. Du lait
///     3. Des œufs
///
/// On ne déclenche qu'à partir de **deux** marqueurs ordinaux, pour ne pas
/// transformer une phrase qui contient juste « premièrement ».
public enum ListFormatter {
    static let ordinals: [[String]] = [
        ["premièrement", "en premier", "firstly", "first of all"],
        ["deuxièmement", "secondement", "en deuxième", "secondly"],
        ["troisièmement", "en troisième", "thirdly"],
        ["quatrièmement", "fourthly"],
        ["cinquièmement", "fifthly"],
        ["sixièmement"],
        ["septièmement"],
        ["huitièmement"],
        ["neuvièmement"],
        ["dixièmement"],
    ]

    public static func apply(to text: String) -> String {
        let alternatives = ordinals.flatMap { $0 }
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
            .joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])[,:]?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count >= 2 else { return text }

        // Introduction = ce qui précède le premier marqueur.
        let firstRange = Range(matches[0].range, in: text)!
        var intro = String(text[..<firstRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        intro = intro.trimmingCharacters(in: CharacterSet(charactersIn: ",:;"))
            .trimmingCharacters(in: .whitespaces)

        var items: [String] = []
        for (index, match) in matches.enumerated() {
            let start = Range(match.range, in: text)!.upperBound
            let end = index + 1 < matches.count ? Range(matches[index + 1].range, in: text)!.lowerBound : text.endIndex
            var item = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
            // Liaisons et ponctuation entre deux éléments : « …pain, deuxièmement », « …lait et troisièmement ».
            item = item.replacingOccurrences(of: #"(?i)[\s,;]*(?:\bet\b|\band\b|\bpuis\b|\bthen\b)?[\s,;]*$"#, with: "", options: .regularExpression)
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
            guard !item.isEmpty else { continue }
            items.append(item.prefix(1).uppercased() + item.dropFirst())
        }
        guard items.count >= 2 else { return text }

        let list = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        if intro.isEmpty { return list }
        return intro + " :\n" + list
    }
}
