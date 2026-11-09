import Foundation

/// Une mise à jour disponible, décrite par une release GitHub.
public struct UpdateInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let tag: String
    public let notes: String
    public let pageURL: URL
    /// Archive de l'app (`Inky-X.Y.Z.zip`).
    public let archiveURL: URL
    /// Empreinte SHA-256 de l'archive (`Inky-X.Y.Z.zip.sha256`).
    public let checksumURL: URL

    public static func == (a: UpdateInfo, b: UpdateInfo) -> Bool { a.tag == b.tag }
}

public enum UpdateError: LocalizedError, Equatable {
    case badResponse(Int)
    case missingAssets
    case checksumMismatch
    case invalidArchive
    case wrongApplication
    case signatureInvalid
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let code): "GitHub a répondu avec le code \(code)."
        case .missingAssets: "La release ne contient pas l'archive attendue."
        case .checksumMismatch: "L'empreinte SHA-256 ne correspond pas : téléchargement corrompu ou modifié."
        case .invalidArchive: "L'archive téléchargée ne contient pas Inky.app."
        case .wrongApplication: "L'archive contient une autre application ou une autre version."
        case .signatureInvalid: "La signature de la nouvelle version n'est pas valide ou ne provient pas du même auteur."
        case .installFailed(let reason): "Installation impossible : \(reason)"
        }
    }
}

/// Interroge l'API publique de GitHub pour connaître la dernière release.
///
/// Confidentialité : la requête ne contient **aucune** donnée personnelle
/// (pas d'identifiant, pas de statistiques). GitHub voit seulement l'adresse
/// IP, comme pour n'importe quelle page web.
public struct UpdateClient: Sendable {
    public let repository: String
    public let currentVersion: SemanticVersion
    let session: URLSession

    public init(repository: String = "ByteOneDev/Inky", currentVersion: SemanticVersion, session: URLSession = .shared) {
        self.repository = repository
        self.currentVersion = currentVersion
        self.session = session
    }

    /// La dernière release si elle est plus récente que la version installée.
    public func checkForUpdate() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub exige un User-Agent : un nom générique, rien d'identifiant.
        request.setValue("Inky-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil } // aucune release publiée
        guard status == 200 else { throw UpdateError.badResponse(status) }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return try Self.update(from: release, currentVersion: currentVersion)
    }

    /// Logique pure (testée) : transforme une release en mise à jour, ou `nil`.
    static func update(from release: GitHubRelease, currentVersion: SemanticVersion) throws -> UpdateInfo? {
        guard !release.draft, !release.prerelease,
              let version = SemanticVersion(release.tag_name),
              version > currentVersion
        else { return nil }

        guard let archive = release.assets.first(where: { $0.name.hasPrefix("Inky-") && $0.name.hasSuffix(".zip") }),
              let checksum = release.assets.first(where: { $0.name == archive.name + ".sha256" })
        else { throw UpdateError.missingAssets }

        return UpdateInfo(
            version: version,
            tag: release.tag_name,
            notes: release.body ?? "",
            pageURL: release.html_url,
            archiveURL: archive.browser_download_url,
            checksumURL: checksum.browser_download_url
        )
    }
}

/// Sous-ensemble du JSON renvoyé par l'API GitHub (noms identiques au JSON).
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    let tag_name: String
    let body: String?
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}
