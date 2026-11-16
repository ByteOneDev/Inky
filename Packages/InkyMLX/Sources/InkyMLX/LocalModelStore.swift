import Foundation
import InkyCore
import Observation
import os

/// Télécharge, liste et supprime les modèles de langage locaux.
/// Rangés dans `~/Library/Application Support/Inky/Models/llm/<éditeur>/<modèle>/`.
@MainActor
@Observable
public final class LocalModelStore {
    public private(set) var installed: Set<String> = []
    /// Progression (0…1) des téléchargements en cours.
    public private(set) var downloads: [String: Double] = [:]
    public var lastError: String?

    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var instances: [String: LocalLanguageModel] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.byteonedev.inky", category: "llm")

    /// Fichier témoin écrit après un téléchargement complet.
    nonisolated static let completionMarker = ".inky-complete"

    public init() { refresh() }

    nonisolated public static var baseFolder: URL { AppPaths.models.appending(path: "llm", directoryHint: .isDirectory) }

    nonisolated public static func folder(for id: String) -> URL {
        baseFolder.appending(path: id, directoryHint: .isDirectory)
    }

    nonisolated static func isComplete(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: completionMarker).path)
    }

    public func isInstalled(_ id: String) -> Bool { installed.contains(id) }

    public func refresh() {
        installed = Set(LocalModelCatalog.models.map(\.id).filter { Self.isComplete(Self.folder(for: $0)) })
    }

    /// Le fournisseur pour ce modèle (une seule instance par modèle, pour
    /// garder le modèle chargé entre deux dictées).
    public func provider(for id: String) -> LocalLanguageModel? {
        guard let info = LocalModelCatalog.info(for: id) else { return nil }
        if let existing = instances[id] { return existing }
        let model = LocalLanguageModel(info: info, folder: Self.folder(for: id))
        instances[id] = model
        return model
    }

    /// Libère tous les modèles chargés, sauf celui-ci.
    public func unloadAll(except id: String? = nil) {
        for (key, model) in instances where key != id {
            Task { await model.unload() }
        }
    }

    public func download(_ id: String) {
        guard tasks[id] == nil else { return }
        downloads[id] = 0
        lastError = nil
        let folder = Self.folder(for: id)
        tasks[id] = Task { [weak self] in
            do {
                try await HuggingFaceDownloader.download(repo: id, to: folder) { fraction in
                    Task { @MainActor in
                        guard let self, self.downloads[id] != nil else { return }
                        self.downloads[id] = fraction
                    }
                }
                try Task.checkCancellation()
                FileManager.default.createFile(atPath: folder.appending(path: Self.completionMarker).path, contents: Data())
                self?.logger.info("Modèle local téléchargé : \(id, privacy: .public)")
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                self?.lastError = "Échec du téléchargement : \(error.localizedDescription)"
            }
            self?.downloads[id] = nil
            self?.tasks[id] = nil
            self?.refresh()
        }
    }

    public func cancelDownload(_ id: String) {
        tasks[id]?.cancel()
    }

    public func delete(_ id: String) {
        if let model = instances[id] { Task { await model.unload() } }
        instances[id] = nil
        try? FileManager.default.removeItem(at: Self.folder(for: id))
        refresh()
    }
}
