import AVFoundation
import Foundation
import InkyCore
import os
#if canImport(Speech)
import Speech
#endif

public enum AppleSpeechEngineError: LocalizedError {
    case unavailable
    case unsupportedLanguage

    public var errorDescription: String? {
        switch self {
        case .unavailable: "La dictée Apple nécessite macOS 26 ou plus récent."
        case .unsupportedLanguage: "Cette langue n'est pas prise en charge par la dictée Apple."
        }
    }
}

/// Moteur de transcription d'Apple (`SpeechAnalyzer`, macOS 26+).
///
/// Pourquoi l'avoir ajouté ? Mesuré sur de vraies dictées (docs/benchmark.md),
/// il est **8 à 12 fois plus rapide** que WhisperKit (0,2 s au lieu de 1,8 s pour
/// 18 s de parole), pour une qualité proche, et il n'y a rien à télécharger :
/// le modèle fait partie de macOS et tourne en local sur le Neural Engine.
///
/// Ses faiblesses, compensées ailleurs : il garde les répétitions (« tu tu »,
/// retirées par `TextCleanup`) et ponctue moins bien les très longues phrases
/// (la restructuration par IA s'en charge).
public actor AppleSpeechEngine: TranscriptionEngine {
    /// Identifiant « modèle » utilisé dans les réglages et le catalogue.
    public static let modelID = "apple-speech"

    private var ready = false
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "transcription")

    public init() {}

    /// Le moteur existe-t-il sur ce Mac (macOS 26+) ?
    public nonisolated static var isSupported: Bool {
        #if canImport(Speech)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    public var isReady: Bool { ready }

    /// Le dossier est ignoré : le modèle fait partie du système. On vérifie
    /// seulement que les ressources de la langue sont installées (macOS les
    /// télécharge depuis Apple la première fois, si besoin).
    public func load(modelAt folder: URL) async throws {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            for locale in [Locale(identifier: "fr_FR"), Locale(identifier: "en_US")] {
                let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    logger.info("Installation des ressources de dictée Apple (\(locale.identifier, privacy: .public))")
                    try await request.downloadAndInstall()
                }
            }
            ready = true
            return
        }
        #endif
        throw AppleSpeechEngineError.unavailable
    }

    public func unload() async {
        ready = false
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> TranscriptionOutput {
        #if canImport(Speech)
        if #available(macOS 26.0, *) {
            let start = Date()
            guard !clip.samples.isEmpty else { return TranscriptionOutput(text: "", language: nil, processingTime: 0) }
            // Pas de détection automatique ici : le moteur travaille par langue.
            // En mode « automatique », on garde le français (langue par défaut).
            let locale = Locale(identifier: options.language == .english ? "en_US" : "fr_FR")
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // Dictionnaire : les mots à reconnaître orientent le modèle.
            if !options.vocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings = [.general: options.vocabulary]
                try await analyzer.setContext(context)
            }

            // Le plus simple et le plus fiable : un fichier audio temporaire
            // (quelques millisecondes à écrire), supprimé juste après.
            let url = FileManager.default.temporaryDirectory.appending(path: "inky-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: url) }
            try Self.write(clip, to: url)
            let file = try AVAudioFile(forReading: url)

            async let collected: String = transcriber.results.reduce(into: "") { text, result in
                text += String(result.text.characters)
            }
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            let text = try await collected.trimmingCharacters(in: .whitespacesAndNewlines)

            let elapsed = Date().timeIntervalSince(start)
            logger.debug("Transcription Apple : \(clip.duration, format: .fixed(precision: 1), privacy: .public) s d'audio en \(elapsed, format: .fixed(precision: 2), privacy: .public) s")
            return TranscriptionOutput(text: text, language: locale.language.languageCode?.identifier, processingTime: elapsed)
        }
        #endif
        throw AppleSpeechEngineError.unavailable
    }

    /// Écrit l'enregistrement (16 kHz mono Float32) dans un fichier audio.
    private static func write(_ clip: AudioClip, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioClip.sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, clip.samples.count)))
        else { throw AppleSpeechEngineError.unavailable }
        buffer.frameLength = AVAudioFrameCount(clip.samples.count)
        clip.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: clip.samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
