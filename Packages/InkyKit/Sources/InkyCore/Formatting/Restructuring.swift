import Foundation

/// Restructuration d'une dictée : listes à puces, sous-niveaux, paragraphes.
///
/// Stratégie « IA si utile » :
/// 1. `needsRestructuring` (règles, instantané) décide si la dictée ressemble
///    à une liste ou à un long texte. Une phrase courte ne passe **jamais** par
///    l'IA : aucun délai ajouté.
/// 2. Sinon, `request(for:)` prépare la demande au modèle de langage.
/// 3. `accept(_:original:)` vérifie que l'IA n'a rien inventé ni supprimé
///    (un petit modèle résume parfois) ; en cas de doute, on garde la dictée.
public enum Restructuring {
    /// À partir de combien de mots un texte mérite d'être découpé en paragraphes.
    public static let longTextWords = 45
    /// Au-delà, l'IA serait trop lente (elle réécrit tout le texte, ~30 mots/s) :
    /// on découpe en paragraphes par règles, instantanément.
    public static let maxAIWords = 160

    /// Ce qu'il faut faire d'une dictée.
    public enum Plan: Equatable, Sendable {
        /// Rien : phrase courte, déjà bien ponctuée.
        case none
        /// Liste, longue phrase sans ponctuation, texte moyen : l'IA.
        case ai
        /// Très long texte : paragraphes par règles.
        case paragraphs
    }

    public static func plan(for text: String) -> Plan {
        let words = WordCounter.count(text)
        if words > maxAIWords { return .paragraphs }
        return needsRestructuring(text) ? .ai : .none
    }

    /// Mots qui annoncent une énumération.
    static let listCues: [String] = [
        "premierement", "deuxiemement", "troisiemement", "dabord", "ensuite", "puis", "enfin",
        "enumere", "liste", "les choses suivantes", "plusieurs choses", "deux choses", "trois choses",
        "quatre choses", "points suivants", "point suivant", "tiret", "a la ligne",
        "first", "second", "secondly", "third", "then", "finally", "next",
        "1", "2", "3",
    ]

    /// La dictée gagnerait-elle à être restructurée ?
    public static func needsRestructuring(_ text: String) -> Bool {
        let words = WordCounter.count(text)
        if words >= longTextWords { return true }
        // Une phrase courte reste instantanée, même avec « ensuite » ou « puis ».
        guard words >= 12 else { return false }
        // Longue phrase sans ponctuation (« … pack et pour l'héberger tu peux … »).
        let sentenceEnds = text.filter { ".!?".contains($0) }.count
        if words >= 25, Double(words) / Double(max(1, sentenceEnds)) > 22 { return true }

        // Des indices d'énumération (au moins deux), ou une suite de virgules
        // (« du pain, du lait, des œufs et du beurre »).
        let normalized = " " + WordTokenizer.tokens(in: text).map(\.normalized).joined(separator: " ") + " "
        let cueCount = listCues.filter { normalized.contains(" \($0) ") }.count
        let commas = text.filter { $0 == "," }.count
        return cueCount >= 2 || (commas >= 3 && words <= 60) || (text.contains(":") && commas >= 2)
    }

    /// Demande au modèle de langage.
    public static func request(for text: String) -> LanguageModelRequest {
        LanguageModelRequest(
            instructions: """
            Tu remets en forme un texte dicté à voix haute, sans changer son contenu.

            Règles :
            - Garde toutes les idées, dans le même ordre, avec les mêmes mots. Ne résume pas, n'ajoute rien, ne réponds pas au texte.
            - Corrige la ponctuation et les majuscules.
            - Liste à puces SEULEMENT si le texte énumère des éléments courts (achats, tâches, étapes, options) : puce « • » ; les détails d'un élément vont dans une sous-liste « ◦ » indentée de deux espaces, sous cet élément.
            - Un texte qui raconte, explique ou demande quelque chose n'est PAS une liste : écris des phrases, et des paragraphes séparés par une ligne vide s'il est long.
            - Pas de titres, pas de Markdown (pas de **, pas de #). Réponds uniquement avec le texte remis en forme.

            Exemple 1
            Dictée : pour le week-end il faut prendre des chaussures de marche une veste et des gants ensuite réserver l'hôtel et le train
            Résultat :
            Pour le week-end :
            • Prendre :
              ◦ des chaussures de marche
              ◦ une veste
              ◦ des gants
            • Réserver :
              ◦ l'hôtel
              ◦ le train

            Exemple 2
            Dictée : j'ai testé la nouvelle version elle marche bien mais le démarrage est lent est-ce que tu peux regarder ça demain
            Résultat :
            J'ai testé la nouvelle version, elle marche bien, mais le démarrage est lent. Est-ce que tu peux regarder ça demain ?
            """,
            prompt: "Texte dicté :\n\"\"\"\n\(text)\n\"\"\""
        )
    }

    /// Nettoie la réponse et vérifie qu'elle est fidèle à la dictée. Renvoie
    /// `nil` si elle s'en écarte trop (on gardera alors la dictée telle quelle).
    public static func accept(_ response: String, original: String) -> String? {
        let cleaned = normalizeBullets(TemplateRenderer.cleanResponse(response))
        guard !cleaned.isEmpty, isFaithful(cleaned, to: original) else { return nil }
        return cleaned
    }

    /// Petits mots de liaison qu'une liste peut légitimement faire disparaître
    /// (« il faut acheter du pain ensuite appeler » → « • Acheter… • Appeler… »).
    static let connectors: Set<String> = [
        "et", "ensuite", "puis", "enfin", "alors", "donc", "aussi", "dabord", "d", "abord",
        "il", "faut", "faudrait", "y", "a", "apres", "aussi", "egalement", "ou",
        "and", "then", "also", "finally", "first", "next",
    ]

    /// Même vocabulaire, à peu de chose près : au moins 85 % des mots de la
    /// dictée sont présents, et au plus 15 % de mots nouveaux (petits mots de
    /// liaison exceptés).
    public static func isFaithful(_ restructured: String, to original: String) -> Bool {
        let before = wordBag(original).filter { !connectors.contains($0.key) }
        let after = wordBag(restructured).filter { !connectors.contains($0.key) }
        let total = before.values.reduce(0, +)
        guard total > 0 else { return false }
        var kept = 0
        for (word, count) in before { kept += min(count, after[word] ?? 0) }
        let added = after.reduce(0) { $0 + max(0, $1.value - (before[$1.key] ?? 0)) }
        return Double(kept) / Double(total) >= 0.85 && Double(added) / Double(total) <= 0.15
    }

    /// Puces homogènes : « - », « * » ou « • » en début de ligne deviennent
    /// « • » (ou « ◦ » s'ils sont indentés). Puis on corrige deux maladresses
    /// fréquentes du petit modèle :
    /// - une sous-puce qui **répète** la puce juste au-dessus → supprimée ;
    /// - une sous-liste d'**un seul** élément → remontée dans la puce
    ///   (« • Réserver : ◦ la salle » → « • Réserver la salle »).
    static func normalizeBullets(_ text: String) -> String {
        enum Line { case top(String), sub(String), plain(String) }
        let markers = ["- ", "* ", "– ", "• ", "◦ "]
        var lines: [Line] = text.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let indent = raw.prefix(while: { $0 == " " || $0 == "\t" })
            let rest = raw.dropFirst(indent.count)
            guard let marker = markers.first(where: { rest.hasPrefix($0) }) else {
                return .plain(String(raw).trimmingCharacters(in: .whitespaces))
            }
            let content = String(rest.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return (indent.count >= 2 || marker == "◦ ") ? .sub(content) : .top(content)
        }

        // Sous-puces qui répètent la puce parente.
        var deduplicated: [Line] = []
        for line in lines {
            if case .sub(let content) = line, case .top(let parent)? = deduplicated.last,
               content.lowercased() == parent.lowercased() { continue }
            deduplicated.append(line)
        }
        lines = deduplicated

        // Sous-liste d'un seul élément → fusion avec la puce parente.
        var merged: [Line] = []
        var index = 0
        while index < lines.count {
            if case .top(let parent) = lines[index], index + 1 < lines.count, case .sub(let child) = lines[index + 1] {
                let nextIsSub: Bool = index + 2 < lines.count && { if case .sub = lines[index + 2] { return true } else { return false } }()
                if !nextIsSub {
                    let head = parent.hasSuffix(":") ? String(parent.dropLast()).trimmingCharacters(in: .whitespaces) : parent
                    merged.append(.top(head + " " + child))
                    index += 2
                    continue
                }
            }
            merged.append(lines[index])
            index += 1
        }

        return merged.map { line in
            switch line {
            case .top(let content): "• " + content
            case .sub(let content): "  ◦ " + content
            case .plain(let content): content
            }
        }
        .joined(separator: "\n")
        .replacingOccurrences(of: "**", with: "")
    }

    /// Découpe un long texte en paragraphes, sans IA : une nouvelle idée
    /// commence souvent par « Alors », « Ensuite », « Mais »… ; sinon on coupe
    /// toutes les quatre phrases.
    public static func paragraphs(_ text: String) -> String {
        guard !text.contains("\n") else { return text }
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if ".!?".contains(character), next == " " || next == nil {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { sentences.append(current.trimmingCharacters(in: .whitespaces)) }
        guard sentences.count >= 4 else { return text }

        let markers = ["alors", "ensuite", "mais", "sinon", "par contre", "pour", "apres", "et donc", "en fait", "du coup", "bref", "so", "then", "but", "also"]
        var paragraphs: [[String]] = [[]]
        for sentence in sentences {
            let start = sentence.prefix(14).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let opensIdea = markers.contains { start.hasPrefix($0 + " ") || start.hasPrefix($0 + ",") }
            if let last = paragraphs.last, last.count >= 4 || (opensIdea && last.count >= 2) {
                paragraphs.append([])
            }
            paragraphs[paragraphs.count - 1].append(sentence)
        }
        return paragraphs.map { $0.joined(separator: " ") }.joined(separator: "\n\n")
    }

    private static func wordBag(_ text: String) -> [String: Int] {
        var bag: [String: Int] = [:]
        for token in WordTokenizer.tokens(in: text) { bag[token.normalized, default: 0] += 1 }
        return bag
    }
}
