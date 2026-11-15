import Foundation
import InkyCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Le modèle de langage d'Apple Intelligence (framework `FoundationModels`).
///
/// Pourquoi lui ?
/// - il tourne **sur le Mac** (Neural Engine), rien ne part sur Internet ;
/// - il est déjà installé avec macOS 26+ : 0 Mo à télécharger pour Inky ;
/// - il parle français.
///
/// Limites : c'est un petit modèle (~3 milliards de paramètres) avec un
/// contexte d'environ 4 000 « tokens » (≈ 3 000 mots, consigne comprise). Il
/// faut qu'Apple Intelligence soit activé dans Réglages Système.
///
/// L'app vise macOS 14 : sur un système plus ancien que macOS 26, le type
/// existe mais répond « indisponible » (`#available` vérifie à l'exécution).
public struct AppleLanguageModel: LanguageModelProvider {
    public init() {}

    public var displayName: String { "Apple Intelligence" }

    public func availability() -> LanguageModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Apple Intelligence est désactivé : Réglages Système › Apple Intelligence et Siri.")
            case .unavailable(.modelNotReady):
                return .unavailable("Le modèle d'Apple Intelligence n'est pas encore prêt (téléchargement en cours ?). Réessaie dans quelques minutes.")
            case .unavailable(.deviceNotEligible):
                return .unavailable("Ce Mac ne prend pas en charge Apple Intelligence.")
            case .unavailable:
                return .unavailable("Apple Intelligence est indisponible pour le moment.")
            }
        }
        #endif
        return .unavailable("Apple Intelligence nécessite macOS 26 ou plus récent.")
    }

    public func generate(_ request: LanguageModelRequest) async throws(InkyCore.LanguageModelError) -> String {
        let status = availability()
        guard case .available = status else {
            if case .unavailable(let reason) = status { throw .unavailable(reason) }
            throw .unavailable("Indisponible")
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            // Une session neuve à chaque fois : chaque dictée est indépendante
            // (une session garde l'historique de la conversation).
            let session = LanguageModelSession(instructions: request.instructions)
            do {
                // Température basse : on veut une réécriture fidèle, pas de la créativité.
                let response = try await session.respond(
                    to: request.prompt,
                    options: GenerationOptions(temperature: 0.3)
                )
                return response.content
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error { throw .tooLong }
                throw .failed(error.localizedDescription)
            } catch {
                throw .failed(error.localizedDescription)
            }
        }
        #endif
        throw .unavailable("Apple Intelligence nécessite macOS 26 ou plus récent.")
    }
}
