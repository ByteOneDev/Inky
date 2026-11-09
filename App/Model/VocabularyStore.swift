import Foundation
import InkyCore
import Observation

/// Le dictionnaire personnel : mots à reconnaître, corrections et snippets.
///
/// Stocké dans un simple fichier JSON lisible
/// (`~/Library/Application Support/Inky/dictionary.json`) : facile à
/// sauvegarder, à copier sur un autre Mac ou à éditer à la main.
@MainActor
@Observable
final class VocabularyStore {
    /// Mots et noms propres à bien orthographier (« Docker », « Kubernetes »…).
    var words: [String] = [] { didSet { save() } }
    /// Corrections et snippets.
    var rules: [ReplacementRule] = [] { didSet { save() } }
    /// Donner aussi les mots à Whisper comme « amorce » (voir `TranscriptionOptions.prompt`).
    /// Peut aider l'orthographe, mais ralentit parfois la transcription.
    var useWordsAsPrompt = true { didSet { save() } }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isLoading = false

    private struct Payload: Codable {
        var words: [String]
        var rules: [ReplacementRule]
        var useWordsAsPrompt: Bool
    }

    init(fileURL: URL = AppPaths.applicationSupport.appending(path: "dictionary.json")) {
        self.fileURL = fileURL
        load()
    }

    var corrections: [ReplacementRule] { rules.filter { $0.kind == .correction } }
    var snippets: [ReplacementRule] { rules.filter { $0.kind == .snippet } }

    /// Amorce donnée au modèle : les mots du dictionnaire, séparés par des virgules.
    var prompt: String? {
        guard useWordsAsPrompt else { return nil }
        let cleaned = words.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }

    func addRule(kind: ReplacementRule.Kind) {
        rules.append(ReplacementRule(kind: kind, trigger: "", replacement: ""))
    }

    func remove(ruleID: UUID) {
        rules.removeAll { $0.id == ruleID }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        isLoading = true
        words = payload.words
        rules = payload.rules
        useWordsAsPrompt = payload.useWordsAsPrompt
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        let payload = Payload(words: words, rules: rules, useWordsAsPrompt: useWordsAsPrompt)
        do {
            try AppPaths.ensureExists(fileURL.deletingLastPathComponent())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            // Rien de critique : on retentera au prochain changement.
        }
    }
}
