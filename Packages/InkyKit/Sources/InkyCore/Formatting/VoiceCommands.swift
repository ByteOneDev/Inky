import Foundation

/// Commandes de ponctuation et de mise en page prononcées à voix haute.
///
/// « Salut à la ligne je t'écris pour… » → « Salut\nJe t'écris pour… »
///
/// On ne retient que des expressions **sans ambiguïté**. « Point » ou
/// « virgule » seuls ne sont pas des commandes : « le point important »,
/// « trois virgule cinq » doivent rester intacts. Whisper ponctue déjà très
/// bien tout seul ; ces commandes servent surtout à la mise en page.
public enum VoiceCommands {
    struct Command {
        let phrases: [String]
        let output: String
        /// Majuscule au mot suivant (nouvelle phrase, nouvelle ligne).
        let capitalizeNext: Bool
    }

    static let commands: [Command] = [
        Command(phrases: ["nouveau paragraphe", "new paragraph"], output: "\n\n", capitalizeNext: true),
        Command(phrases: ["point à la ligne"], output: ".\n", capitalizeNext: true),
        Command(phrases: ["à la ligne", "retour à la ligne", "nouvelle ligne", "new line"], output: "\n", capitalizeNext: true),
        Command(phrases: ["point d'interrogation", "question mark"], output: "?", capitalizeNext: true),
        Command(phrases: ["point d'exclamation", "exclamation mark", "exclamation point"], output: "!", capitalizeNext: true),
        Command(phrases: ["point-virgule", "point virgule", "semicolon"], output: ";", capitalizeNext: false),
        Command(phrases: ["ouvrez les guillemets", "ouvrir les guillemets", "open quote"], output: "« ", capitalizeNext: false),
        Command(phrases: ["fermez les guillemets", "fermer les guillemets", "close quote"], output: " »", capitalizeNext: false),
        Command(phrases: ["ouvrez la parenthèse", "ouvrir la parenthèse", "open parenthesis"], output: "(", capitalizeNext: false),
        Command(phrases: ["fermez la parenthèse", "fermer la parenthèse", "close parenthesis"], output: ")", capitalizeNext: false),
    ]

    public static func apply(to text: String) -> String {
        var result = text
        for command in commands {
            for phrase in command.phrases {
                let words = NSRegularExpression.escapedPattern(for: phrase).replacingOccurrences(of: " ", with: "\\s+")
                // On avale la ponctuation que Whisper met souvent autour de la
                // commande : « Salut, à la ligne. Je… » → « Salut\nJe… »
                let pattern = "[,.]?\\s*(?<![\\p{L}\\p{N}])\(words)(?![\\p{L}\\p{N}])[,.]?\\s*"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                result = replace(regex, in: result, with: command.output, capitalizeNext: command.capitalizeNext)
            }
        }
        // Pas d'espace avant une fin de ligne, ni en tout début de ligne.
        result = result.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with output: String, capitalizeNext: Bool) -> String {
        var result = text
        // Parcours à l'envers : les remplacements ne décalent pas les positions restantes.
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            var replacement = output
            // Espacement autour des signes : « ? » « ! » collés au mot précédent, puis une espace.
            if ["?", "!", ";", ")", " »"].contains(output) { replacement += " " }
            // Signes ouvrants : une espace avant (le motif a avalé celle du texte).
            if output == "(" || output == "« " { replacement = " " + output }
            result.replaceSubrange(range, with: replacement)
            if capitalizeNext {
                let after = result.index(range.lowerBound, offsetBy: replacement.count, limitedBy: result.endIndex) ?? result.endIndex
                if after < result.endIndex, result[after].isLowercase {
                    result.replaceSubrange(after...after, with: result[after].uppercased())
                }
            }
        }
        return result
    }
}
