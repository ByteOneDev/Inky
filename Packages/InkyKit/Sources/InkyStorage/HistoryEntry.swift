import Foundation
import GRDB

/// Une dictée enregistrée dans l'historique.
///
/// Les protocoles GRDB font le lien avec SQLite :
/// - `FetchableRecord` : on sait construire un `HistoryEntry` depuis une ligne ;
/// - `PersistableRecord` : on sait l'insérer / le mettre à jour ;
/// - `Codable` : GRDB associe automatiquement propriétés et colonnes par leur nom.
public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "transcription"

    /// Clé primaire auto-incrémentée par SQLite (`nil` avant insertion).
    public var id: Int64?
    public var createdAt: Date
    /// Texte final, inséré dans l'app.
    public var text: String
    /// Texte brut sorti de Whisper, avant nettoyage (utile pour comprendre une erreur).
    public var rawText: String
    /// Durée de l'audio, en secondes.
    public var audioDuration: Double
    /// Temps de transcription, en secondes.
    public var processingTime: Double
    public var modelID: String
    public var language: String?
    public var appName: String?
    public var appBundleID: String?
    /// Nom du fichier audio dans `Application Support/Inky/Audio/` (si conservé).
    public var audioFileName: String?

    public init(
        id: Int64? = nil,
        createdAt: Date = Date(),
        text: String,
        rawText: String,
        audioDuration: Double,
        processingTime: Double,
        modelID: String,
        language: String? = nil,
        appName: String? = nil,
        appBundleID: String? = nil,
        audioFileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.rawText = rawText
        self.audioDuration = audioDuration
        self.processingTime = processingTime
        self.modelID = modelID
        self.language = language
        self.appName = appName
        self.appBundleID = appBundleID
        self.audioFileName = audioFileName
    }

    /// Après insertion, SQLite nous donne l'identifiant attribué.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Noms de colonnes typés, pour écrire les requêtes sans fautes de frappe.
    public enum Columns {
        static let createdAt = Column(CodingKeys.createdAt)
        static let text = Column(CodingKeys.text)
        static let audioFileName = Column(CodingKeys.audioFileName)
    }
}
