import Foundation
import GRDB
import Testing
@testable import InkyStorage

struct HistoryStoreTests {
    /// Base SQLite en mémoire : rapide, et repart de zéro à chaque test.
    func makeStore() throws -> HistoryStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try HistoryStore(dbQueue: DatabaseQueue(), audioDirectory: dir)
    }

    func entry(_ text: String, daysAgo: Int = 0) -> HistoryEntry {
        HistoryEntry(
            createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            text: text, rawText: text, audioDuration: 1, processingTime: 0.2, modelID: "test"
        )
    }

    @Test func insertAssignsIDAndFetchesNewestFirst() throws {
        let store = try makeStore()
        let first = try store.add(entry("ancien", daysAgo: 1))
        try store.add(entry("récent"))
        #expect(first.id != nil)
        #expect(try store.fetch().map(\.text) == ["récent", "ancien"])
    }

    @Test func searchFiltersByText() throws {
        let store = try makeStore()
        try store.add(entry("Lance le serveur Docker"))
        try store.add(entry("Bonjour"))
        #expect(try store.fetch(search: "docker").map(\.text) == ["Lance le serveur Docker"])
    }

    @Test func purgeRemovesExpiredEntriesAndAudio() throws {
        let store = try makeStore()
        var old = entry("vieux", daysAgo: 40)
        old.audioFileName = "old.m4a"
        let audioURL = store.audioDirectory.appending(path: "old.m4a")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data([1, 2, 3]))
        try store.add(old)
        try store.add(entry("neuf", daysAgo: 2))

        #expect(try store.purge(retention: .oneMonth) == 1)
        #expect(try store.fetch().map(\.text) == ["neuf"])
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test func foreverKeepsEverything() throws {
        let store = try makeStore()
        try store.add(entry("très vieux", daysAgo: 5000))
        #expect(try store.purge(retention: .forever) == 0)
        #expect(try store.purge(retention: .never) == 1)
    }
}
