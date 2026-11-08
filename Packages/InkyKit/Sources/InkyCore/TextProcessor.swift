import Foundation

/// Informations sur le contexte de la dictée, utiles pour adapter le texte
/// (en v0.2 : choisir un prompt LLM différent pour Slack ou pour un IDE).
public struct ProcessingContext: Sendable {
    public var appBundleID: String?
    public var appName: String?
    public var language: String?

    public init(appBundleID: String? = nil, appName: String? = nil, language: String? = nil) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.language = language
    }
}

/// Une étape de transformation du texte transcrit.
///
/// Les processeurs se chaînent : nettoyage de base → remplacements du
/// dictionnaire → reformulation par LLM (v0.2). Chaque étape est remplaçable.
public protocol TextProcessor: Sendable {
    func process(_ text: String, context: ProcessingContext) async throws -> String
}
