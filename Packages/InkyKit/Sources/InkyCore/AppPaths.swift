import Foundation

/// Emplacements des données d'Inky sur le disque.
/// Tout est dans `~/Library/Application Support/Inky/` : un seul dossier à
/// supprimer pour effacer toute trace de l'app.
public enum AppPaths {
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Inky", directoryHint: .isDirectory)
    }

    /// Modèles Whisper téléchargés.
    public static var models: URL { applicationSupport.appending(path: "Models", directoryHint: .isDirectory) }

    /// Base SQLite de l'historique.
    public static var historyDatabase: URL { applicationSupport.appending(path: "history.sqlite") }

    /// Fichiers audio associés à l'historique.
    public static var audio: URL { applicationSupport.appending(path: "Audio", directoryHint: .isDirectory) }

    /// Crée le dossier s'il n'existe pas et le renvoie.
    @discardableResult
    public static func ensureExists(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
