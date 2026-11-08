import Foundation
import InkyCore
import Observation
import WhisperKit
import os

/// Télécharge, liste et supprime les modèles Whisper.
///
/// Les modèles ne sont pas dans l'app (ils pèsent des centaines de Mo) : ils
/// sont récupérés à la demande depuis Hugging Face, dans
/// `~/Library/Application Support/Inky/Models/`.
///
/// `@Observable` : SwiftUI redessine automatiquement la vue quand une
/// propriété lue par la vue change (progression, liste des modèles installés…).
@MainActor
@Observable
public final class ModelManager {
    /// Identifiants des modèles complètement téléchargés.
    public private(set) var installed: Set<String> = []
    /// Progression (0…1) des téléchargements en cours, par identifiant.
    public private(set) var downloads: [String: Double] = [:]
    /// Dernière erreur, à afficher.
    public var lastError: String?

    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.byteonedev.inky", category: "models")

    /// Fichier témoin écrit **après** un téléchargement complet : un dossier sans
    /// ce fichier est un téléchargement interrompu, à ne pas utiliser.
    static let completionMarker = ".inky-complete"

    public init() {
        refresh()
    }

    /// Dossier racine passé à WhisperKit. Il y range les fichiers sous
    /// `models/argmaxinc/whisperkit-coreml/<modèle>/` (convention Hugging Face).
    public var downloadBase: URL { AppPaths.models }

    /// Dossier d'un modèle donné.
    public func folder(for modelID: String) -> URL {
        downloadBase
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: ModelCatalog.repository, directoryHint: .isDirectory)
            .appending(path: modelID, directoryHint: .isDirectory)
    }

    public func isInstalled(_ modelID: String) -> Bool { installed.contains(modelID) }

    /// Relit le disque pour savoir quels modèles sont présents.
    public func refresh() {
        let fm = FileManager.default
        installed = Set(ModelCatalog.models.map(\.id).filter { id in
            fm.fileExists(atPath: folder(for: id).appending(path: Self.completionMarker).path)
        })
    }

    /// Lance le téléchargement d'un modèle (sans bloquer l'interface).
    public func download(_ modelID: String) {
        guard tasks[modelID] == nil else { return }
        downloads[modelID] = 0
        lastError = nil

        tasks[modelID] = Task { [weak self] in
            guard let self else { return }
            do {
                try AppPaths.ensureExists(self.downloadBase)
                let folder = try await WhisperKit.download(
                    variant: modelID,
                    downloadBase: self.downloadBase,
                    from: ModelCatalog.repository,
                    progressCallback: { [weak self] progress in
                        // Appelé sur un thread quelconque → on revient sur le MainActor.
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            if self?.downloads[modelID] != nil { self?.downloads[modelID] = fraction }
                        }
                    }
                )
                try Task.checkCancellation()
                // Le « tokenizer » (table mots ↔ nombres) n'est pas dans le dossier du
                // modèle : WhisperKit le télécharge depuis le dépôt OpenAI au premier
                // chargement. On le récupère MAINTENANT, au même endroit, pour que le
                // chargement du modèle fonctionne ensuite entièrement hors ligne.
                _ = try await ModelUtilities.loadTokenizer(for: Self.tokenizerVariant(for: modelID), tokenizerFolder: self.downloadBase)
                try Task.checkCancellation()
                FileManager.default.createFile(atPath: folder.appending(path: Self.completionMarker).path, contents: Data())
                self.logger.info("Modèle téléchargé : \(modelID, privacy: .public)")
            } catch is CancellationError {
                self.logger.info("Téléchargement annulé : \(modelID, privacy: .public)")
            } catch {
                self.lastError = "Échec du téléchargement de \(modelID) : \(error.localizedDescription)"
                self.logger.error("Échec du téléchargement : \(error.localizedDescription, privacy: .public)")
            }
            self.downloads[modelID] = nil
            self.tasks[modelID] = nil
            self.refresh()
        }
    }

    /// Famille de modèle, pour savoir quel tokenizer récupérer.
    /// (Tous les « large-v3 », turbo compris, partagent celui de large-v3.)
    static func tokenizerVariant(for modelID: String) -> ModelVariant {
        if modelID.contains("large-v3") { return .largev3 }
        if modelID.contains("small") { return .small }
        if modelID.contains("base") { return .base }
        if modelID.contains("medium") { return .medium }
        return .tiny
    }

    public func cancelDownload(_ modelID: String) {
        tasks[modelID]?.cancel()
    }

    /// Supprime un modèle du disque.
    public func delete(_ modelID: String) {
        try? FileManager.default.removeItem(at: folder(for: modelID))
        refresh()
    }

    /// Place occupée par un modèle installé, en octets.
    public func diskUsage(of modelID: String) -> Int64 {
        let url = folder(for: modelID)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
