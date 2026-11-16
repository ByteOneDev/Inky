import Foundation
import InkyCore
import MLXLLM
import MLXLMCommon
import Tokenizers
import os

/// Un modèle de langage ouvert (Mistral, Llama, Qwen…) qui tourne **sur le
/// Mac** grâce à MLX, sur le GPU d'Apple Silicon. Rien ne quitte la machine.
///
/// Le modèle (2 à 4 Go en mémoire) est chargé à la première demande, puis
/// gardé prêt ; il est libéré après 15 minutes sans utilisation.
public final class LocalLanguageModel: LanguageModelProvider {
    public let info: LocalModelInfo
    public let folder: URL
    private let runner: Runner

    public init(info: LocalModelInfo, folder: URL) {
        self.info = info
        self.folder = folder
        self.runner = Runner(folder: folder)
    }

    public var displayName: String { "\(info.displayName) (\(info.vendor))" }

    public func availability() -> LanguageModelAvailability {
        LocalModelStore.isComplete(folder)
            ? .available
            : .unavailable("Le modèle \(info.displayName) n'est pas téléchargé (Prompts IA › Modèle d'IA).")
    }

    public func generate(_ request: LanguageModelRequest) async throws(LanguageModelError) -> String {
        guard availability().isAvailable else { throw .unavailable("Modèle non téléchargé.") }
        do {
            return try await runner.generate(request)
        } catch let error as LanguageModelError {
            throw error
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    /// Charge le modèle maintenant (pour que la première dictée soit rapide).
    public func preload() async {
        try? await runner.load()
    }

    public func unload() async {
        await runner.unload()
    }
}

/// Possède le modèle chargé. Un `actor` : une seule génération à la fois.
private actor Runner {
    let folder: URL
    private var container: ModelContainer?
    private var unloadTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "llm")

    init(folder: URL) { self.folder = folder }

    func load() async throws {
        if container != nil { return }
        let start = Date()
        container = try await loadModelContainer(from: folder, using: TransformersTokenizerLoader())
        logger.info("Modèle local chargé en \(Date().timeIntervalSince(start), format: .fixed(precision: 1), privacy: .public) s")
    }

    func unload() {
        container = nil
        unloadTask?.cancel()
        unloadTask = nil
    }

    func generate(_ request: LanguageModelRequest) async throws -> String {
        try await load()
        guard let container else { throw LanguageModelError.failed("Modèle non chargé.") }
        let session = ChatSession(
            container,
            instructions: request.instructions,
            // Température basse : réécriture fidèle. Limite de longueur : sécurité.
            generateParameters: GenerateParameters(maxTokens: 1500, temperature: 0.3),
            // Qwen3 « réfléchit » à voix haute par défaut : on le désactive.
            additionalContext: ["enable_thinking": false]
        )
        let output = try await session.respond(to: request.prompt, images: [], videos: [], audios: [])
        scheduleUnload()
        return Self.stripThinking(output)
    }

    /// Libère la mémoire après 15 minutes sans demande.
    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }

    /// Retire un éventuel bloc de réflexion `<think>…</think>`.
    static func stripThinking(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Charge le tokenizer d'un dossier de modèle avec swift-transformers et
/// l'adapte au protocole de MLX (ce que fait la macro
/// `#huggingFaceTokenizerLoader()`, écrit ici en clair).
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream: upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
