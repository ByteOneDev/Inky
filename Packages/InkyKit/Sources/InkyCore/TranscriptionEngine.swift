import Foundation

/// Langue de dictée.
public enum DictationLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Whisper devine la langue. Pratique, mais peu fiable sur une phrase très
    /// courte : il vaut mieux forcer la langue quand on la connaît.
    case automatic
    case french
    case english

    public var id: String { rawValue }

    /// Code ISO 639-1 attendu par Whisper (`nil` = détection automatique).
    public var whisperCode: String? {
        switch self {
        case .automatic: nil
        case .french: "fr"
        case .english: "en"
        }
    }

    public var displayName: String {
        switch self {
        case .automatic: "Détection automatique"
        case .french: "Français"
        case .english: "Anglais"
        }
    }
}

/// Paramètres d'une transcription.
public struct TranscriptionOptions: Sendable {
    public var language: DictationLanguage
    /// Texte d'amorce : oriente le vocabulaire du modèle (noms propres, jargon).
    /// Prévu pour le dictionnaire personnel de la v0.2.
    public var prompt: String?

    public init(language: DictationLanguage, prompt: String? = nil) {
        self.language = language
        self.prompt = prompt
    }
}

/// Résultat brut d'une transcription.
public struct TranscriptionOutput: Sendable {
    public var text: String
    /// Langue détectée (ou imposée), code ISO.
    public var language: String?
    /// Temps de calcul pur, en secondes.
    public var processingTime: TimeInterval

    public init(text: String, language: String?, processingTime: TimeInterval) {
        self.text = text
        self.language = language
        self.processingTime = processingTime
    }
}

/// Le contrat que doit respecter tout moteur de transcription.
///
/// C'est un protocole `Actor` : un moteur possède un état lourd (le modèle chargé
/// en mémoire) et ne doit être utilisé que par une tâche à la fois. Un acteur
/// garantit cette exclusion mutuelle sans qu'on écrive de verrou à la main.
///
/// Pour ajouter whisper.cpp, Parakeet ou SpeechAnalyzer plus tard, il suffira
/// d'écrire un nouvel acteur conforme à ce protocole.
public protocol TranscriptionEngine: Actor {
    /// Charge (et préchauffe) le modèle situé dans ce dossier.
    /// Opération lente (plusieurs secondes) : à faire au lancement, pas à la dictée.
    func load(modelAt folder: URL) async throws

    /// Libère la mémoire occupée par le modèle.
    func unload() async

    /// Vrai si un modèle est prêt à transcrire.
    var isReady: Bool { get }

    /// Transcrit un enregistrement.
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> TranscriptionOutput
}
