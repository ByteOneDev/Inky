import Foundation
import InkyCore
import WhisperKit
import os

public enum WhisperKitEngineError: LocalizedError {
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .notLoaded: "Aucun modèle de transcription n'est chargé."
        }
    }
}

/// Moteur de transcription basé sur WhisperKit (CoreML).
///
/// Clé de la latence : le modèle est chargé **une fois** au lancement puis
/// gardé en mémoire. Charger large-v3-turbo prend plusieurs secondes (et bien
/// plus la toute première fois, quand CoreML compile le modèle pour le Neural
/// Engine de ta puce) ; transcrire une phrase, une fraction de seconde.
public actor WhisperKitEngine: TranscriptionEngine {
    private var whisper: WhisperKit?
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "transcription")

    public init() {}

    public var isReady: Bool { whisper != nil }

    public func load(modelAt folder: URL) async throws {
        await unload()
        let start = Date()

        let config = WhisperKitConfig(
            modelFolder: folder.path,
            tokenizerFolder: AppPaths.models, // tokenizer pré-téléchargé par ModelManager
            verbose: false,
            prewarm: true,   // force la compilation/spécialisation CoreML maintenant
            load: true,      // puis charge réellement les modèles en mémoire
            download: false  // le ModelManager s'occupe des téléchargements
        )
        let whisper = try await WhisperKit(config)
        self.whisper = whisper

        // Échauffement : la toute première inférence est plus lente (allocation
        // des tampons, caches). On la fait maintenant sur 1 s de silence, pour
        // que la première vraie dictée soit déjà rapide.
        _ = try? await whisper.transcribe(
            audioArray: [Float](repeating: 0, count: Int(AudioClip.sampleRate)),
            decodeOptions: DecodingOptions(language: "fr", withoutTimestamps: true)
        )
        logger.info("Modèle chargé en \(Date().timeIntervalSince(start), format: .fixed(precision: 1), privacy: .public) s")
    }

    public func unload() async {
        await whisper?.unloadModels()
        whisper = nil
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> TranscriptionOutput {
        guard let whisper else { throw WhisperKitEngineError.notLoaded }
        let start = Date()

        // Le dictionnaire (v0.2) passera par des « prompt tokens » : du texte
        // donné au décodeur comme s'il précédait l'audio, ce qui biaise le
        // vocabulaire (orthographe des noms propres, jargon).
        var promptTokens: [Int]?
        if let prompt = options.prompt, !prompt.isEmpty, let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let language = options.language.whisperCode
        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,                    // décodage déterministe (le plus probable)
            usePrefillPrompt: true,            // impose la langue/tâche au décodeur
            detectLanguage: language == nil,   // détection seulement en mode automatique
            skipSpecialTokens: true,           // pas de <|fr|>, <|endoftext|>… dans le texte
            withoutTimestamps: true,           // on n'a pas besoin des horodatages : plus rapide
            promptTokens: promptTokens,
            suppressBlank: true,
            noSpeechThreshold: 0.6             // segments jugés « sans parole » → ignorés
        )

        let results = try await whisper.transcribe(audioArray: clip.samples, decodeOptions: decodeOptions)
        let text = results.map(\.text).joined(separator: " ")
        let detected = results.first?.language ?? language

        let elapsed = Date().timeIntervalSince(start)
        logger.debug("Transcription : \(clip.duration, format: .fixed(precision: 1), privacy: .public) s d'audio en \(elapsed, format: .fixed(precision: 2), privacy: .public) s")
        return TranscriptionOutput(text: text, language: detected, processingTime: elapsed)
    }
}
