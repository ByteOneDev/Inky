import Foundation

/// Un modèle de langage local proposé dans l'app.
public struct LocalModelInfo: Identifiable, Hashable, Sendable {
    /// Dépôt Hugging Face (versions MLX quantifiées en 4 bits de `mlx-community`).
    public let id: String
    public let displayName: String
    public let vendor: String
    /// Taille du téléchargement, en Go.
    public let sizeGB: Double
    public let summary: String
    public var isRecommended = false
}

/// Liste **choisie** de modèles ouverts, tous en 4 bits (poids compressés :
/// ~4 fois plus légers, perte de qualité faible). Entre 1 et 4 Go, pour tenir
/// en mémoire à côté du reste sur un Mac de 16 Go.
///
/// Absents volontairement : Claude (Anthropic) et GPT-4/5 (OpenAI) n'existent
/// pas en local ; le seul modèle ouvert d'OpenAI (gpt-oss) pèse 11 Go.
public enum LocalModelCatalog {
    public static let models: [LocalModelInfo] = [
        LocalModelInfo(
            id: "mlx-community/Ministral-3-3B-Instruct-2512-4bit",
            displayName: "Ministral 3 3B",
            vendor: "Mistral AI",
            sizeGB: 2.8,
            summary: "Le plus rapide et le meilleur en français lors de nos tests (mail en 2,9 s).",
            isRecommended: true
        ),
        LocalModelInfo(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            displayName: "Qwen3 4B",
            vendor: "Alibaba",
            sizeGB: 2.3,
            summary: "Bon pour structurer, plus lent et parfois familier en français."
        ),
        LocalModelInfo(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B",
            vendor: "Meta",
            sizeGB: 1.8,
            summary: "Léger et rapide, correct en français."
        ),
        LocalModelInfo(
            id: "mlx-community/Phi-4-mini-instruct-4bit",
            displayName: "Phi-4 mini",
            vendor: "Microsoft",
            sizeGB: 2.2,
            summary: "Bon pour structurer et reformuler, surtout en anglais."
        ),
        LocalModelInfo(
            id: "mlx-community/gemma-3-4b-it-qat-4bit",
            displayName: "Gemma 3 4B",
            vendor: "Google",
            sizeGB: 3.0,
            summary: "Très bon en français, un peu plus lent que Ministral."
        ),
        LocalModelInfo(
            id: "mlx-community/Qwen3-1.7B-4bit",
            displayName: "Qwen3 1.7B",
            vendor: "Alibaba",
            sizeGB: 1.0,
            summary: "Le plus léger : très rapide, qualité moindre."
        ),
        LocalModelInfo(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            displayName: "Mistral 7B",
            vendor: "Mistral AI",
            sizeGB: 4.1,
            summary: "Le plus gros : meilleure rédaction, plus lent et gourmand en mémoire."
        ),
    ]

    public static func info(for id: String) -> LocalModelInfo? {
        models.first { $0.id == id }
    }
}
