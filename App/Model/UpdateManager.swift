import AppKit
import InkyUpdates
import Observation
import os

/// Côté app des mises à jour : quand vérifier, quoi afficher, quand installer.
/// La logique réseau et la vérification sont dans le module `InkyUpdates`.
@MainActor
@Observable
final class UpdateManager {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case downloading(UpdateInfo)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let logger = Logger(subsystem: "com.byteonedev.inky", category: "updates")
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    /// Version de l'app en cours d'exécution (Info.plist).
    let currentVersion: SemanticVersion = {
        let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return SemanticVersion(string) ?? SemanticVersion("0.0.0")!
    }()

    /// En développement (lancée depuis Xcode), on vérifie mais on n'installe pas :
    /// on écraserait le build de DerivedData.
    var canInstall: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    var availableUpdate: UpdateInfo? {
        if case .available(let info) = state { return info }
        return nil
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Vérifie 15 s après le lancement, puis toutes les 24 h, si l'option est active.
    func startAutomaticChecks() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                guard let self else { return }
                if self.settings.autoCheckUpdates {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        state = .checking
        do {
            let update = try await UpdateClient(currentVersion: currentVersion).checkForUpdate()
            lastCheck = Date()
            if let update {
                logger.info("Mise à jour disponible : \(update.version.description, privacy: .public)")
                state = .available(update)
                if !userInitiated && settings.autoInstallUpdates && canInstall {
                    await install(update)
                }
            } else {
                state = .upToDate
            }
        } catch {
            logger.error("Vérification des mises à jour : \(error.localizedDescription, privacy: .public)")
            // Une vérification automatique qui échoue (hors ligne…) reste silencieuse.
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    func install(_ update: UpdateInfo) async {
        guard canInstall else {
            state = .failed("Installation désactivée dans un build de développement.")
            return
        }
        state = .downloading(update)
        let currentApp = Bundle.main.bundleURL
        let installer = UpdateInstaller(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.byteonedev.inky")
        do {
            let newApp = try await installer.download(update, verifyingAgainst: currentApp)
            try installer.installAndRelaunch(newApp: newApp, replacing: currentApp, pid: ProcessInfo.processInfo.processIdentifier)
            logger.info("Installation de \(update.version.description, privacy: .public), redémarrage")
            NSApp.terminate(nil)
        } catch {
            logger.error("Installation : \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
