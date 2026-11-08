import Foundation

/// Nettoyage de base, sans IA, appliqué à toute transcription.
///
/// Trois problèmes courants de Whisper :
/// 1. **Hallucinations sur le silence** : entraîné sur des sous-titres, Whisper
///    « invente » parfois des génériques (« Sous-titres réalisés par la
///    communauté d'Amara.org », « Merci d'avoir regardé »…).
/// 2. **Balises d'ambiance** : « [Musique] », « (rires) », « *applaudissements* ».
/// 3. **Hésitations** : « euh », « hum »… (les modèles turbo en retirent déjà
///    beaucoup, on finit le travail).
public struct TextCleanup: TextProcessor {
    public var removeFillers: Bool

    public init(removeFillers: Bool = true) {
        self.removeFillers = removeFillers
    }

    /// Phrases typiques des hallucinations, comparées en minuscules.
    /// On ne supprime que si la transcription **entière** correspond, pour ne
    /// jamais effacer quelqu'un qui dicterait volontairement « merci ».
    static let hallucinations: [String] = [
        "sous-titres réalisés par la communauté d'amara.org",
        "sous-titrage st' 501",
        "sous-titrage société radio-canada",
        "merci d'avoir regardé cette vidéo",
        "merci d'avoir regardé",
        "abonnez-vous",
        "thanks for watching",
        "thank you for watching",
        "subtitles by the amara.org community",
        "...",
    ]

    public func process(_ text: String, context: ProcessingContext = .init()) async throws -> String {
        clean(text)
    }

    /// Version synchrone (pratique pour les tests).
    public func clean(_ text: String) -> String {
        var result = text

        // 1. Balises entre crochets / parenthèses / astérisques : [Musique], (rires)…
        result = result.replacingOccurrences(
            of: #"\[[^\]]*\]|\([^)]*(musique|music|rires?|laughs?|applaudissements|applause|silence|bruit|noise)[^)]*\)|\*[^*]+\*"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        // 2. Hésitations, en mots isolés uniquement (\b = frontière de mot).
        //    On retire aussi la virgule qui suit souvent : « euh, je pense ».
        if removeFillers {
            result = result.replacingOccurrences(
                of: #"(?i)\b(euh+|heu+|hum+|hmm+|uh+|um+|erm+)\b[,.]?\s*"#,
                with: "",
                options: .regularExpression
            )
        }

        // 3. Espaces multiples → un seul, espaces superflus aux extrémités.
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Ponctuation orpheline au début (« , je pense » après retrait d'un euh).
        while let first = result.first, ",;".contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }

        // 5. Majuscule initiale si on a retiré le début de phrase.
        if let first = result.first, first.isLowercase, text.trimmingCharacters(in: .whitespaces).first?.isUppercase == true {
            result = first.uppercased() + result.dropFirst()
        }

        // 6. Hallucination complète → texte vide.
        let normalized = result.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
        if Self.hallucinations.contains(where: { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .!")) == normalized }) {
            return ""
        }
        return result
    }
}
