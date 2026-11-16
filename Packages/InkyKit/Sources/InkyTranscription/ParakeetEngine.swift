import FluidAudio
import Foundation
import InkyCore
import os

/// Moteur de transcription Parakeet TDT 0.6B v3 (NVIDIA), via FluidAudio.
///
/// Pourquoi lui ? C'est un modèle « transducteur » (TDT) et non un modèle
/// encodeur-décodeur comme Whisper : il émet le texte au fil de l'audio au lieu
/// de le réécrire mot à mot, ce qui le rend **beaucoup plus rapide**, avec une
/// très bonne qualité en français (25 langues européennes), ponctuation et
/// majuscules comprises. FluidAudio l'a converti pour CoreML : il tourne sur le
/// Neural Engine, en local. Environ 480 Mo sur disque.
public actor ParakeetEngine: TranscriptionEngine {
    public static let modelID = "nvidia-parakeet-tdt-0.6b-v3"
    /// Nom du dossier imposé par FluidAudio pour ce modèle.
    public static let folderName = "parakeet-tdt-0.6b-v3"

    private var manager: AsrManager?
    private var decoderLayers = 2
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "transcription")

    public init() {}

    public var isReady: Bool { manager != nil }

    public func load(modelAt folder: URL) async throws {
        await unload()
        let start = Date()
        let models = try await AsrModels.load(from: folder, version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        // Échauffement : la première inférence alloue les tampons du Neural Engine.
        var state = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
        _ = try? await manager.transcribe([Float](repeating: 0, count: Int(AudioClip.sampleRate)), decoderState: &state)
        self.manager = manager
        decoderLayers = models.version.decoderLayers
        logger.info("Parakeet chargé en \(Date().timeIntervalSince(start), format: .fixed(precision: 1), privacy: .public) s")
    }

    public func unload() async {
        manager = nil
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> TranscriptionOutput {
        guard let manager else { throw WhisperKitEngineError.notLoaded }
        let start = Date()
        // Indice de langue : écarte les jetons d'un autre alphabet. En mode
        // automatique, on n'en donne pas (Parakeet reconnaît la langue seul).
        let language: Language? = switch options.language {
        case .french: .french
        case .english: .english
        case .automatic: nil
        }
        var state = try TdtDecoderState(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(clip.samples, decoderState: &state, language: language)
        let elapsed = Date().timeIntervalSince(start)
        logger.debug("Transcription Parakeet : \(clip.duration, format: .fixed(precision: 1), privacy: .public) s d'audio en \(elapsed, format: .fixed(precision: 2), privacy: .public) s")
        return TranscriptionOutput(text: result.text, language: language?.rawValue, processingTime: elapsed)
    }

    /// Télécharge les fichiers du modèle dans `folder` (depuis Hugging Face).
    public static func download(to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await AsrModels.download(to: folder, version: .v3) { update in
            progress(update.fractionCompleted)
        }
    }

    /// Les fichiers du modèle sont-ils tous présents ?
    public static func isInstalled(at folder: URL) -> Bool {
        AsrModels.modelsExist(at: folder, version: .v3)
    }
}
