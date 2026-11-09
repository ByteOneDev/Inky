import Foundation

/// Une règle de remplacement du dictionnaire personnel.
///
/// Deux usages, une seule mécanique :
/// - **Correction** : Whisper écrit mal un mot → on le corrige systématiquement
///   (« gît hub » → « GitHub », « mac os » → « macOS »).
/// - **Snippet** : une phrase courte prononcée → un texte long inséré
///   (« mon adresse mail » → « prenom.nom@exemple.fr »).
public struct ReplacementRule: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case correction
        case snippet
    }

    public var id: UUID
    public var kind: Kind
    /// Ce que Whisper écrit (ou ce qu'on prononce pour un snippet).
    public var trigger: String
    /// Ce qu'on veut obtenir à la place.
    public var replacement: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), kind: Kind, trigger: String, replacement: String, isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.trigger = trigger
        self.replacement = replacement
        self.isEnabled = isEnabled
    }
}

/// Applique les règles de remplacement.
public enum Replacements {
    /// Remplace chaque déclencheur par son texte, **en mots entiers** et sans
    /// tenir compte de la casse ni d'une ponctuation finale ajoutée par Whisper
    /// (« Mon adresse mail. » déclenche le snippet « mon adresse mail »).
    public static func apply(_ rules: [ReplacementRule], to text: String) -> String {
        var result = text
        // Les déclencheurs les plus longs d'abord : « adresse mail pro » doit
        // passer avant « adresse mail ».
        let active = rules
            .filter { $0.isEnabled && !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }

        for rule in active {
            let trigger = NSRegularExpression.escapedPattern(for: rule.trigger.trimmingCharacters(in: .whitespaces))
                // Les espaces du déclencheur acceptent n'importe quel espacement.
                .replacingOccurrences(of: "\\ ", with: "\\s+")
                .replacingOccurrences(of: " ", with: "\\s+")
            // (?<![\p{L}\p{N}]) … (?![\p{L}\p{N}]) : « mot entier » qui fonctionne
            // aussi avec les lettres accentuées (contrairement à \b dans certains cas).
            var pattern = "(?<![\\p{L}\\p{N}])" + trigger + "(?![\\p{L}\\p{N}])"
            if rule.kind == .snippet {
                // Un snippet avale la ponctuation que Whisper met juste après.
                pattern += "[.!?]?"
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let template = NSRegularExpression.escapedTemplate(for: rule.replacement)
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }
}
