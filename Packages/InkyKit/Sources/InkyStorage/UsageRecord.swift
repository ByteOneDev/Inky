import Foundation
import GRDB
import InkyCore

/// Une ligne de statistiques : une par dictée, **sans le texte**.
///
/// Pourquoi une table à part de l'historique ? L'historique est supprimé au
/// bout de la durée choisie (1 mois par défaut) ou pas conservé du tout. Les
/// statistiques, elles, doivent survivre (« 12 000 mots dictés depuis le
/// début »). On n'y garde donc que des nombres, rien de privé.
public struct UsageRecord: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "usage"

    public var id: Int64?
    public var createdAt: Date
    public var wordCount: Int
    /// Durée de parole, en secondes.
    public var audioDuration: Double
    public var appName: String?
    public var appBundleID: String?

    public init(id: Int64? = nil, createdAt: Date = Date(), wordCount: Int, audioDuration: Double, appName: String? = nil, appBundleID: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.wordCount = wordCount
        self.audioDuration = audioDuration
        self.appName = appName
        self.appBundleID = appBundleID
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var sample: UsageSample {
        UsageSample(date: createdAt, words: wordCount, duration: audioDuration, appName: appName)
    }
}
