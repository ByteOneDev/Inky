import Foundation
import GRDB
import InkyCore
import os

/// Durée de conservation de l'historique.
public enum HistoryRetention: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = 0          // ne rien garder du tout
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30
    case threeMonths = 90
    case oneYear = 365
    case forever = -1

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .never: "Ne pas conserver"
        case .oneDay: "1 jour"
        case .oneWeek: "1 semaine"
        case .oneMonth: "1 mois"
        case .threeMonths: "3 mois"
        case .oneYear: "1 an"
        case .forever: "Toujours"
        }
    }

    /// Date avant laquelle les entrées doivent être supprimées (`nil` = jamais).
    public func cutoff(from now: Date = Date()) -> Date? {
        switch self {
        case .forever: nil
        case .never: .distantFuture
        default: Calendar.current.date(byAdding: .day, value: -rawValue, to: now)
        }
    }
}

/// Accès à l'historique des dictées, stocké dans une base SQLite.
///
/// `DatabaseQueue` (GRDB) sérialise tous les accès à la base : une seule
/// opération à la fois, sur une file dédiée. Simple et largement suffisant pour
/// une app qui écrit une ligne par dictée.
public final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue
    /// Dossier des fichiers audio associés.
    public let audioDirectory: URL
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "history")

    /// Base sur disque (usage normal).
    public convenience init() throws {
        try AppPaths.ensureExists(AppPaths.applicationSupport)
        try self.init(
            dbQueue: DatabaseQueue(path: AppPaths.historyDatabase.path),
            audioDirectory: AppPaths.ensureExists(AppPaths.audio)
        )
    }

    /// Initialiseur général (les tests passent une base en mémoire).
    public init(dbQueue: DatabaseQueue, audioDirectory: URL) throws {
        self.dbQueue = dbQueue
        self.audioDirectory = audioDirectory
        try Self.migrator.migrate(dbQueue)
    }

    /// Les migrations décrivent l'évolution du schéma, version après version.
    /// Règle d'or : ne **jamais** modifier une migration déjà publiée ; en
    /// ajouter une nouvelle (« v2 », « v3 »…). GRDB retient lesquelles ont été
    /// appliquées dans une table interne.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "transcription") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("text", .text).notNull()
                t.column("rawText", .text).notNull()
                t.column("audioDuration", .double).notNull()
                t.column("processingTime", .double).notNull()
                t.column("modelID", .text).notNull()
                t.column("language", .text)
                t.column("appName", .text)
                t.column("appBundleID", .text)
                t.column("audioFileName", .text)
            }
        }
        return migrator
    }

    // MARK: - Écriture

    @discardableResult
    public func add(_ entry: HistoryEntry) throws -> HistoryEntry {
        try dbQueue.write { db in
            var entry = entry
            try entry.insert(db)
            return entry
        }
    }

    public func delete(_ entry: HistoryEntry) throws {
        _ = try dbQueue.write { db in try entry.delete(db) }
        deleteAudio(entry.audioFileName)
    }

    public func deleteAll() throws {
        _ = try dbQueue.write { db in try HistoryEntry.deleteAll(db) }
        if let files = try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// Supprime les entrées (et leur audio) plus anciennes que la durée de conservation.
    /// Renvoie le nombre d'entrées supprimées.
    @discardableResult
    public func purge(retention: HistoryRetention, now: Date = Date()) throws -> Int {
        guard let cutoff = retention.cutoff(from: now) else { return 0 }
        let expired = try dbQueue.write { db -> [HistoryEntry] in
            let request = HistoryEntry.filter(HistoryEntry.Columns.createdAt < cutoff)
            let entries = try request.fetchAll(db)
            try request.deleteAll(db)
            return entries
        }
        for entry in expired { deleteAudio(entry.audioFileName) }
        if !expired.isEmpty { logger.info("Historique : \(expired.count, privacy: .public) entrée(s) expirée(s) supprimée(s)") }
        return expired.count
    }

    // MARK: - Lecture

    /// Entrées les plus récentes, filtrées par un texte de recherche optionnel.
    public func fetch(search: String = "", limit: Int = 500) throws -> [HistoryEntry] {
        try dbQueue.read { db in
            try Self.request(search: search, limit: limit).fetchAll(db)
        }
    }

    /// Observe la base : `onChange` est rappelé à chaque modification (insertion,
    /// suppression…), ce qui permet à l'interface de se mettre à jour toute seule.
    /// Garder l'objet renvoyé : l'observation s'arrête quand il est libéré.
    @MainActor
    public func observe(search: String, limit: Int = 500, onChange: @escaping @MainActor ([HistoryEntry]) -> Void) -> HistoryObservation {
        let cancellable = ValueObservation
            .tracking { db in try Self.request(search: search, limit: limit).fetchAll(db) }
            .start(in: dbQueue, scheduling: .immediate, onError: { [logger] error in
                logger.error("Observation de l'historique : \(error.localizedDescription, privacy: .public)")
            }, onChange: onChange)
        return HistoryObservation(cancellable)
    }

    private static func request(search: String, limit: Int) -> QueryInterfaceRequest<HistoryEntry> {
        var request = HistoryEntry.order(HistoryEntry.Columns.createdAt.desc).limit(limit)
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // LIKE '%mot%' : recherche simple, insensible à la casse pour l'ASCII.
            // (Pour un historique énorme, on passerait à la recherche plein texte FTS5.)
            request = request.filter(HistoryEntry.Columns.text.like("%\(trimmed)%"))
        }
        return request
    }

    // MARK: - Audio

    public func audioURL(for entry: HistoryEntry) -> URL? {
        guard let name = entry.audioFileName else { return nil }
        let url = audioDirectory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Nom de fichier unique pour un nouvel enregistrement.
    public func newAudioFileName() -> String { UUID().uuidString + ".m4a" }

    private func deleteAudio(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: audioDirectory.appending(path: name))
    }
}

/// Jeton d'observation : tant qu'on le garde, l'historique est surveillé.
/// (Enveloppe le type GRDB pour que l'app n'ait pas à importer GRDB.)
public final class HistoryObservation {
    private let cancellable: AnyDatabaseCancellable
    init(_ cancellable: AnyDatabaseCancellable) { self.cancellable = cancellable }
    public func cancel() { cancellable.cancel() }
}
