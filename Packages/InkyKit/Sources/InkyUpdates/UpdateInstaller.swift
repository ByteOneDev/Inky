import CryptoKit
import Foundation
import Security

/// Télécharge, vérifie puis installe une mise à jour.
///
/// Chaîne de confiance, du plus simple au plus fort :
/// 1. **HTTPS** vers github.com : personne ne modifie le fichier en route.
/// 2. **SHA-256** : l'archive correspond exactement à celle publiée.
/// 3. **Signature de code** : si la version installée est signée avec un
///    certificat (et non « ad hoc »), la nouvelle version DOIT être signée par
///    le même certificat. Un attaquant qui publierait une fausse release sans
///    la clé privée serait refusé.
public struct UpdateInstaller: Sendable {
    public let bundleIdentifier: String
    let session: URLSession

    public init(bundleIdentifier: String, session: URLSession = .shared) {
        self.bundleIdentifier = bundleIdentifier
        self.session = session
    }

    /// Télécharge et vérifie la mise à jour. Renvoie l'app prête à installer.
    public func download(_ update: UpdateInfo, verifyingAgainst currentApp: URL) async throws -> URL {
        let workDir = FileManager.default.temporaryDirectory.appending(path: "InkyUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // 1. Archive + empreinte
        let (archiveTemp, _) = try await session.download(from: update.archiveURL)
        let archive = workDir.appending(path: "Inky.zip")
        try FileManager.default.moveItem(at: archiveTemp, to: archive)
        let (checksumData, _) = try await session.data(from: update.checksumURL)

        // 2. SHA-256 : le fichier .sha256 contient « <empreinte hex>  <nom> ».
        let expected = String(decoding: checksumData, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
        let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, expected == actual else { throw UpdateError.checksumMismatch }

        // 3. Extraction avec ditto (l'outil d'Apple qui préserve signatures et attributs).
        let extracted = workDir.appending(path: "extracted")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let newApp = extracted.appending(path: "Inky.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw UpdateError.invalidArchive }

        // 4. Bonne app, bonne version ?
        guard let info = Bundle(url: newApp)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              let versionString = info["CFBundleShortVersionString"] as? String,
              SemanticVersion(versionString) == update.version
        else { throw UpdateError.wrongApplication }

        // 5. Signature
        try Self.verifySignature(of: newApp, matching: currentApp)
        return newApp
    }

    /// Remplace l'app installée par la nouvelle version, puis relance.
    ///
    /// Une app ne peut pas se remplacer elle-même pendant qu'elle tourne
    /// proprement : on lance un petit script shell indépendant qui attend la
    /// fin de notre processus, échange les dossiers, puis rouvre l'app.
    /// Après cet appel, l'app doit se terminer (`NSApp.terminate`).
    public func installAndRelaunch(newApp: URL, replacing currentApp: URL, pid: Int32) throws {
        let parent = currentApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.installFailed("pas le droit d'écrire dans \(parent.path)")
        }
        let script = """
        #!/bin/sh
        # Script de mise à jour d'Inky (généré automatiquement).
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        OLD="\(currentApp.path).old"
        rm -rf "$OLD"
        mv "\(currentApp.path)" "$OLD" || exit 1
        if mv "\(newApp.path)" "\(currentApp.path)"; then
          rm -rf "$OLD"
        else
          mv "$OLD" "\(currentApp.path)"   # échec : on remet l'ancienne version
        fi
        xattr -dr com.apple.quarantine "\(currentApp.path)" 2>/dev/null
        open "\(currentApp.path)"
        """
        let scriptURL = newApp.deletingLastPathComponent().appending(path: "install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run() // le script survit à la fermeture d'Inky
    }

    // MARK: - Signature de code

    /// Vérifie la nouvelle app ; exige le même certificat que l'app actuelle
    /// quand celle-ci n'est pas signée « ad hoc ».
    static func verifySignature(of newApp: URL, matching currentApp: URL) throws {
        let newCode = try staticCode(newApp)
        let currentCode = try staticCode(currentApp)

        var requirement: SecRequirement?
        if !isAdHoc(currentCode) {
            // « Exigence désignée » de l'app actuelle, par ex. :
            // identifier "com.byteonedev.inky" and certificate leaf = H"1afc…"
            guard SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess else {
                throw UpdateError.signatureInvalid
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else {
            throw UpdateError.signatureInvalid
        }
    }

    static func staticCode(_ url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.signatureInvalid
        }
        return code
    }

    static func isAdHoc(_ code: SecStaticCode) -> Bool {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return true }
        let flags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adHocFlag: UInt32 = 0x0002 // kSecCodeSignatureAdhoc
        return flags & adHocFlag != 0 || dict[kSecCodeInfoCertificates as String] == nil
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidArchive }
    }
}
