import Foundation
import InkyCore
import InkyHotkeys
import InkyStorage
import InkyTranscription
import Observation

/// Position de la pastille à l'écran.
enum OverlayPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: "En haut à gauche"
        case .top: "En haut"
        case .topRight: "En haut à droite"
        case .left: "À gauche"
        case .right: "À droite"
        case .bottomLeft: "En bas à gauche"
        case .bottom: "En bas (centre)"
        case .bottomRight: "En bas à droite"
        }
    }
}

/// Tous les réglages de l'app, sauvegardés dans `UserDefaults`.
///
/// Chaque propriété relit sa valeur au démarrage et l'écrit dès qu'elle change
/// (`didSet`). Grâce à `@Observable`, l'interface et le contrôleur réagissent
/// immédiatement à toute modification.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    // — Raccourcis —
    var pushToTalkShortcut: Shortcut { didSet { save(pushToTalkShortcut, Keys.pushToTalk) } }
    var handsFreeShortcut: Shortcut { didSet { save(handsFreeShortcut, Keys.handsFree) } }

    // — Audio —
    /// UID du micro choisi ; `nil` = micro par défaut du système.
    var inputDeviceUID: String? { didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDevice) } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: Keys.playSounds) } }

    // — Transcription —
    var selectedModelID: String { didSet { defaults.set(selectedModelID, forKey: Keys.model) } }
    var language: DictationLanguage { didSet { save(language, Keys.language) } }
    var removeFillers: Bool { didSet { defaults.set(removeFillers, forKey: Keys.removeFillers) } }

    // — Insertion —
    var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) } }
    /// Délai avant restauration du presse-papier, en millisecondes.
    var restoreDelayMs: Int { didSet { defaults.set(restoreDelayMs, forKey: Keys.restoreDelay) } }

    // — Pastille —
    var overlayPosition: OverlayPosition { didSet { save(overlayPosition, Keys.overlayPosition) } }

    // — Historique —
    var historyRetention: HistoryRetention { didSet { save(historyRetention, Keys.retention) } }
    var keepAudio: Bool { didSet { defaults.set(keepAudio, forKey: Keys.keepAudio) } }

    // — Premier lancement —
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pushToTalkShortcut = Self.load(Keys.pushToTalk, from: defaults) ?? .defaultPushToTalk
        handsFreeShortcut = Self.load(Keys.handsFree, from: defaults) ?? .defaultHandsFree
        inputDeviceUID = defaults.string(forKey: Keys.inputDevice)
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        selectedModelID = defaults.string(forKey: Keys.model) ?? ModelCatalog.recommended.id
        language = Self.load(Keys.language, from: defaults) ?? .french
        removeFillers = defaults.object(forKey: Keys.removeFillers) as? Bool ?? true
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        restoreDelayMs = defaults.object(forKey: Keys.restoreDelay) as? Int ?? 350
        overlayPosition = Self.load(Keys.overlayPosition, from: defaults) ?? .bottom
        historyRetention = Self.load(Keys.retention, from: defaults) ?? .oneMonth
        keepAudio = defaults.object(forKey: Keys.keepAudio) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    }

    // MARK: - Persistance des types complexes (encodés en JSON)

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private enum Keys {
        static let pushToTalk = "shortcut.pushToTalk"
        static let handsFree = "shortcut.handsFree"
        static let inputDevice = "audio.inputDeviceUID"
        static let playSounds = "audio.playSounds"
        static let model = "transcription.model"
        static let language = "transcription.language"
        static let removeFillers = "transcription.removeFillers"
        static let restoreClipboard = "insertion.restoreClipboard"
        static let restoreDelay = "insertion.restoreDelayMs"
        static let overlayPosition = "overlay.position"
        static let retention = "history.retention"
        static let keepAudio = "history.keepAudio"
        static let onboarding = "onboarding.completed"
    }
}
