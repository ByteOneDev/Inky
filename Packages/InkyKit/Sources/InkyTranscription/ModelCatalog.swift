import Foundation

/// Description d'un modèle de transcription proposé dans l'app.
public struct WhisperModelInfo: Identifiable, Hashable, Sendable {
    /// Moteur qui fait tourner ce modèle.
    public enum Engine: Sendable { case whisper, parakeet }

    /// Nom du dossier sur Hugging Face (dépôt `argmaxinc/whisperkit-coreml`).
    public let id: String
    public let displayName: String
    /// Taille du téléchargement, en mégaoctets.
    public let sizeMB: Int
    public let summary: String
    public let isRecommended: Bool
    public var engine: Engine = .whisper
    /// Éditeur du modèle (affiché dans les réglages).
    public var vendor = "OpenAI"
}

/// Liste **choisie** de modèles. Le dépôt en contient une trentaine (versions
/// anglaises seules, distil, variantes) : on n'en garde que quelques-uns,
/// tous multilingues, du plus léger au plus précis.
///
/// Les suffixes `_626MB`, `_216MB` désignent des versions **compressées**
/// (quantification des poids) : 2 à 3 fois plus légères, pour une perte de
/// qualité très faible.
public enum ModelCatalog {
    public static let repository = "argmaxinc/whisperkit-coreml"

    public static let models: [WhisperModelInfo] = [
        WhisperModelInfo(
            id: ParakeetEngine.modelID,
            displayName: "Parakeet TDT v3",
            sizeMB: 480,
            summary: "Très rapide et précis, ponctuation comprise. 25 langues européennes dont le français.",
            isRecommended: true,
            engine: .parakeet,
            vendor: "NVIDIA"
        ),
        WhisperModelInfo(
            id: "openai_whisper-large-v3-v20240930_626MB",
            displayName: "Whisper Large v3 Turbo (compressé)",
            sizeMB: 626,
            summary: "Très bonne qualité, mais plus lent (1 à 3 s par dictée).",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-large-v3-v20240930",
            displayName: "Whisper Large v3 Turbo",
            sizeMB: 1619,
            summary: "Version non compressée : qualité maximale, 2,5 × plus lourde, gain faible.",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-small_216MB",
            displayName: "Whisper Small (compressé)",
            sizeMB: 217,
            summary: "Léger. Correct pour des phrases simples, plus d'erreurs sur les noms propres.",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeMB: 146,
            summary: "Très rapide, qualité moyenne en français.",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-tiny",
            displayName: "Whisper Tiny",
            sizeMB: 76,
            summary: "Pour tester. Nombreuses erreurs.",
            isRecommended: false
        ),
    ]

    public static var recommended: WhisperModelInfo { models.first { $0.isRecommended }! }

    public static func info(for id: String) -> WhisperModelInfo? {
        models.first { $0.id == id }
    }
}
