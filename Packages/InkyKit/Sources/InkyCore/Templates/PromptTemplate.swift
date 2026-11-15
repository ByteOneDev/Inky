import Foundation

/// Un **modèle de prompt** : une phrase déclencheuse + une consigne écrite à
/// l'avance dans les réglages.
///
/// On commence la dictée par la phrase déclencheuse, et ce qu'on dit ensuite
/// est combiné avec la consigne :
///
///     « Prompt engineering, je veux un script qui renomme mes photos »
///       └─ déclencheur ─┘ └──────────── contenu dicté ────────────┘
///
/// - avec l'IA (`usesAI`) : la consigne et le contenu partent au modèle de
///   langage local, qui rédige le texte final (un prompt propre, un mail…) ;
/// - sans IA : la consigne est un simple gabarit, où `{texte}` est remplacé par
///   le contenu dicté.
public struct PromptTemplate: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Nom affiché dans les réglages.
    public var name: String
    /// Phrase à prononcer au **début** de la dictée.
    public var trigger: String
    /// Consigne pour l'IA, ou gabarit avec `{texte}` si `usesAI` est faux.
    public var instructions: String
    public var usesAI: Bool
    /// Donner aussi à l'IA le texte déjà présent dans le champ (pour compléter
    /// un mail en cours d'écriture, par exemple).
    public var includesFieldText: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: String,
        instructions: String,
        usesAI: Bool = true,
        includesFieldText: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.instructions = instructions
        self.usesAI = usesAI
        self.includesFieldText = includesFieldText
        self.isEnabled = isEnabled
    }

    /// Emplacement du contenu dicté dans un gabarit sans IA.
    public static let placeholder = "{texte}"
}

// MARK: - Modèles fournis au premier lancement

extension PromptTemplate {
    /// Exemples proposés au premier lancement (modifiables et supprimables).
    public static let examples: [PromptTemplate] = [
        PromptTemplate(
            name: "Prompt pour une IA",
            trigger: "prompt engineering",
            instructions: """
            Transforme la demande dictée en un prompt clair et structuré pour un assistant IA. \
            Organise-le en sections courtes : Contexte, Objectif, Contraintes, Format de réponse attendu. \
            Corrige les hésitations et les répétitions. N'exécute pas la demande : écris uniquement le prompt, \
            dans la langue de la dictée.
            """
        ),
        PromptTemplate(
            name: "Mail professionnel",
            trigger: "mail pro",
            instructions: """
            Rédige un e-mail professionnel, poli et concis à partir des idées dictées. \
            Commence par une formule d'appel, termine par une formule de politesse adaptée, sans signature. \
            Ne mets pas d'objet. Écris dans la langue de la dictée.
            """
        ),
        PromptTemplate(
            name: "Compléter le texte en cours",
            trigger: "complète",
            instructions: """
            Écris la suite du texte déjà présent, en suivant ce que je dicte (des idées ou des consignes). \
            Garde le même ton, la même langue et le même niveau de formalité. \
            Ne répète pas le texte existant : écris uniquement la suite à insérer.
            """,
            includesFieldText: true
        ),
    ]
}

// MARK: - Reconnaissance du déclencheur

/// Résultat d'une reconnaissance : le modèle et ce qui a été dicté après la phrase.
public struct TemplateMatch: Equatable, Sendable {
    public var template: PromptTemplate
    public var content: String
}

public enum TemplateMatcher {
    /// Cherche un modèle actif dont la phrase déclencheuse **ouvre** la dictée.
    ///
    /// La comparaison ignore la casse, les accents et la ponctuation, car
    /// Whisper écrit aussi bien « Prompt engineering, » que « prompt
    /// engineering. ». Si plusieurs déclencheurs conviennent, le plus long
    /// gagne (« mail pro » avant « mail »).
    public static func match(_ text: String, in templates: [PromptTemplate]) -> TemplateMatch? {
        let words = WordTokenizer.tokens(in: text)
        let candidates = templates
            .filter(\.isEnabled)
            .map { ($0, WordTokenizer.tokens(in: $0.trigger).map(\.normalized)) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.1.count > $1.1.count }

        for (template, triggerWords) in candidates where triggerWords.count <= words.count {
            let opening = words.prefix(triggerWords.count).map(\.normalized)
            guard Array(opening) == triggerWords else { continue }
            let end = words[triggerWords.count - 1].range.upperBound
            return TemplateMatch(template: template, content: cleanContent(String(text[end...])))
        }
        return nil
    }

    /// Retire la ponctuation laissée entre le déclencheur et la suite
    /// (« , je veux » → « Je veux »).
    static func cleanContent(_ text: String) -> String {
        // Seulement au début : la ponctuation finale de la dictée est gardée.
        let leading = Set(" \n\t,.;:!?-–—…")
        let trimmed = String(text.drop(while: { leading.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst()
    }
}

// MARK: - Construction de la requête

public enum TemplateRenderer {
    /// Gabarit sans IA : remplace `{texte}` par le contenu dicté (ou l'ajoute à
    /// la fin si le gabarit n'a pas d'emplacement).
    public static func fill(_ template: PromptTemplate, content: String) -> String {
        let model = template.instructions
        if model.contains(PromptTemplate.placeholder) {
            return model.replacingOccurrences(of: PromptTemplate.placeholder, with: content)
        }
        return content.isEmpty ? model : model + "\n\n" + content
    }

    /// Requête pour le modèle de langage : les **instructions** (le « rôle ») et
    /// le **prompt** (la matière à traiter).
    ///
    /// - Parameter fieldText: texte déjà présent avant le curseur, si le modèle
    ///   le demande et que l'app l'expose.
    public static func request(for template: PromptTemplate, content: String, fieldText: String?) -> LanguageModelRequest {
        let instructions = """
        Tu es l'assistant de rédaction d'une app de dictée vocale. Le texte que tu produis est inséré \
        tel quel à l'emplacement du curseur de l'utilisateur.
        Règles : réponds uniquement avec le texte à insérer, sans introduction, sans commentaire, \
        sans guillemets autour et sans balises Markdown de bloc de code.

        Consigne de l'utilisateur :
        \(template.instructions)
        """

        var prompt = ""
        if let fieldText, !fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "Texte déjà écrit (avant le curseur) :\n\"\"\"\n\(fieldText)\n\"\"\"\n\n"
        }
        prompt += content.isEmpty
            ? "Rien n'a été dicté en plus : applique la consigne."
            : "Dictée de l'utilisateur :\n\"\"\"\n\(content)\n\"\"\""
        return LanguageModelRequest(instructions: instructions, prompt: prompt)
    }

    /// Nettoie la réponse du modèle : certains ajoutent des guillemets ou un
    /// bloc de code autour du texte malgré la consigne.
    public static func cleanResponse(_ response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count >= 6 {
            text = String(text.dropFirst(3).dropLast(3))
            // Retirer l'éventuel langage après les ``` (« ```markdown »).
            if let newline = text.firstIndex(of: "\n"), !text[..<newline].contains(" ") {
                text = String(text[text.index(after: newline)...])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"\"\"", "\"\"\""), ("\"", "\""), ("«", "»")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > open.count + close.count {
            text = String(text.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

// MARK: - Découpage en mots

/// Découpe un texte en mots (suites de lettres ou de chiffres), en gardant
/// leur position dans le texte d'origine.
enum WordTokenizer {
    struct Token {
        let range: Range<String.Index>
        /// Minuscules, sans accents : « Complète » → « complete ».
        let normalized: String
    }

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let isWordCharacter = text[index].isLetter || text[index].isNumber
            if isWordCharacter, start == nil { start = index }
            if !isWordCharacter, let s = start {
                tokens.append(makeToken(text, s..<index))
                start = nil
            }
            index = text.index(after: index)
        }
        if let s = start { tokens.append(makeToken(text, s..<text.endIndex)) }
        return tokens
    }

    private static func makeToken(_ text: String, _ range: Range<String.Index>) -> Token {
        let normalized = text[range].folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Token(range: range, normalized: normalized)
    }
}
