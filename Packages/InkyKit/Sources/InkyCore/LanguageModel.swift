import Foundation

/// Ce qu'on demande à un modèle de langage : un rôle et une matière à traiter.
public struct LanguageModelRequest: Equatable, Sendable {
    /// Instructions « système » : le rôle et les règles à suivre.
    public var instructions: String
    /// Le texte à traiter.
    public var prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}

/// Le modèle est-il utilisable, et sinon pourquoi (message pour l'utilisateur).
public enum LanguageModelAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool { self == .available }
}

public enum LanguageModelError: Error, LocalizedError, Equatable {
    case unavailable(String)
    /// Le texte dépasse ce que le modèle peut lire d'un coup.
    case tooLong
    /// Le modèle a refusé de répondre (filtres de sécurité).
    case refused
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .tooLong: "Texte trop long pour le modèle."
        case .refused: "Le modèle a refusé de traiter ce texte."
        case .failed(let message): message
        }
    }
}

/// Un modèle de langage capable de réécrire du texte (Apple Intelligence
/// aujourd'hui ; Ollama ou une API demain, sans toucher au reste de l'app).
public protocol LanguageModelProvider: Sendable {
    /// Nom affiché (« Apple Intelligence »).
    var displayName: String { get }
    func availability() -> LanguageModelAvailability
    func generate(_ request: LanguageModelRequest) async throws(LanguageModelError) -> String
}
