import Foundation
import InkyCore
import Observation

/// Les modèles de prompts, stockés dans un fichier JSON lisible
/// (`~/Library/Application Support/Inky/templates.json`), comme le dictionnaire.
@MainActor
@Observable
final class TemplateStore {
    var templates: [PromptTemplate] = [] { didSet { save() } }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isLoading = false

    init(fileURL: URL = AppPaths.applicationSupport.appending(path: "templates.json")) {
        self.fileURL = fileURL
        load()
    }

    func add() -> PromptTemplate {
        let template = PromptTemplate(name: "Nouveau modèle", trigger: "", instructions: "")
        templates.append(template)
        return template
    }

    func remove(_ id: UUID) {
        templates.removeAll { $0.id == id }
    }

    /// Remet les exemples fournis (sans toucher aux modèles de l'utilisateur).
    func restoreExamples() {
        let existing = Set(templates.map { $0.trigger.lowercased() })
        templates += PromptTemplate.examples
            .filter { !existing.contains($0.trigger.lowercased()) }
            .map { var t = $0; t.id = UUID(); return t }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            // Premier lancement : quelques exemples pour comprendre le principe.
            templates = PromptTemplate.examples
            return
        }
        isLoading = true
        var loaded = (try? JSONDecoder().decode([PromptTemplate].self, from: data)) ?? []
        // Exemples d'une version précédente, jamais modifiés : on passe aux
        // nouvelles consignes (meilleures avec le modèle d'Apple).
        var migrated = false
        for index in loaded.indices {
            if let newer = PromptTemplate.legacyExampleInstructions[loaded[index].instructions] {
                loaded[index].instructions = newer
                migrated = true
            }
        }
        templates = loaded
        isLoading = false
        if migrated { save() }
    }

    private func save() {
        guard !isLoading else { return }
        do {
            try AppPaths.ensureExists(fileURL.deletingLastPathComponent())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(templates).write(to: fileURL, options: .atomic)
        } catch {
            // Rien de critique : on retentera au prochain changement.
        }
    }
}
