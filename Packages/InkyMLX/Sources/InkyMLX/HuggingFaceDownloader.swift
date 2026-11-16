import Foundation

/// Télécharge un dépôt de modèle depuis Hugging Face, fichier par fichier,
/// dans un dossier choisi par Inky (et non dans le cache global de Hugging
/// Face) : tout reste dans `~/Library/Application Support/Inky/Models/`.
///
/// Seuls les fichiers utiles sont récupérés : poids (`.safetensors`),
/// configuration et tokenizer (`.json`, `.jinja`, `tokenizer.model`).
enum HuggingFaceDownloader {
    struct RepoFile: Decodable {
        let rfilename: String
        let size: Int64?
    }

    private struct RepoInfo: Decodable {
        let siblings: [RepoFile]
    }

    enum DownloadError: LocalizedError {
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let file): "Téléchargement impossible : \(file)"
            }
        }
    }

    static func isUseful(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".safetensors") || lower.hasSuffix(".json") || lower.hasSuffix(".jinja")
            || lower == "tokenizer.model" || lower.hasSuffix("/tokenizer.model")
    }

    /// Télécharge `repo` dans `folder`. `progress` reçoit une fraction 0…1,
    /// pondérée par la taille des fichiers. Les fichiers déjà complets sont sautés.
    static func download(repo: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let api = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        let (data, response) = try await URLSession.shared.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadError.badResponse(repo) }
        let files = try JSONDecoder().decode(RepoInfo.self, from: data).siblings.filter { isUseful($0.rfilename) }

        let total = max(1, files.reduce(Int64(0)) { $0 + ($1.size ?? 1) })
        var done: Int64 = 0
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for file in files {
            try Task.checkCancellation()
            let destination = folder.appending(path: file.rfilename)
            let expected = file.size ?? -1
            if let existing = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(existing) == expected {
                done += expected
                progress(Double(done) / Double(total))
                continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

            let remote = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file.rfilename)")!
            let start = done
            let delegate = ProgressDelegate { written in
                progress(Double(start + written) / Double(total))
            }
            let (temporary, fileResponse) = try await URLSession.shared.download(from: remote, delegate: delegate)
            guard (fileResponse as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadError.badResponse(file.rfilename) }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            done += file.size ?? 1
            progress(Double(done) / Double(total))
        }
    }

    /// Relaie l'avancement d'un fichier (octets reçus).
    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
        let onWrite: @Sendable (Int64) -> Void
        init(onWrite: @escaping @Sendable (Int64) -> Void) { self.onWrite = onWrite }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            onWrite(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
