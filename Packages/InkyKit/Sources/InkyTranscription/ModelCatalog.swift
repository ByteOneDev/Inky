import Foundation

/// Description d'un modèle Whisper proposé dans l'app.
public struct WhisperModelInfo: Identifiable, Hashable, Sendable {
    /// Nom du dossier sur Hugging Face (dépôt `argmaxinc/whisperkit-coreml`).
    public let id: String
    public let displayName: String
    /// Taille du téléchargement, en mégaoctets.
    public let sizeMB: Int
    public let summary: String
    public let isRecommended: Bool
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
            id: "openai_whisper-large-v3-v20240930_626MB",
            displayName: "Large v3 Turbo (compressé)",
            sizeMB: 626,
            summary: "Recommandé. Excellente qualité en français et en anglais, rapide sur Apple Silicon.",
            isRecommended: true
        ),
        WhisperModelInfo(
            id: "openai_whisper-large-v3-v20240930",
            displayName: "Large v3 Turbo",
            sizeMB: 1619,
            summary: "Version non compressée : qualité maximale, 2,5 × plus lourde, gain faible.",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-small_216MB",
            displayName: "Small (compressé)",
            sizeMB: 217,
            summary: "Léger. Correct pour des phrases simples, plus d'erreurs sur les noms propres.",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-base",
            displayName: "Base",
            sizeMB: 146,
            summary: "Très rapide, qualité moyenne en français.",
            isRecommended: false
        ),
        WhisperModelInfo(
            id: "openai_whisper-tiny",
            displayName: "Tiny",
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
