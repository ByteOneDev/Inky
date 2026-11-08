import Foundation

/// Pourquoi une insertion a échoué. Dans tous les cas, le texte reste
/// récupérable (presse-papier ou historique) : on ne perd jamais une dictée.
public enum InsertionError: Error, Equatable, Sendable {
    /// Un champ sécurisé (mot de passe) ou la « saisie clavier sécurisée » de
    /// Terminal est actif : macOS bloque les frappes simulées.
    case secureInputActive
    /// Inky n'a pas l'autorisation Accessibilité, indispensable pour simuler ⌘V.
    case accessibilityNotGranted
    /// Impossible de créer l'événement clavier.
    case eventCreationFailed
}

/// Le contrat d'une méthode d'insertion de texte dans l'app active.
///
/// `@MainActor` : le presse-papier (`NSPasteboard`) et l'envoi d'événements
/// clavier se font sur le thread principal.
@MainActor
public protocol TextInserter: AnyObject {
    /// Insère `text` à l'emplacement du curseur de l'app au premier plan.
    func insert(_ text: String) async throws(InsertionError)
}
