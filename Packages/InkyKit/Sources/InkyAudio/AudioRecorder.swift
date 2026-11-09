@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import InkyCore
import os

public enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case deviceSelectionFailed(OSStatus)
    case invalidInputFormat
    case engineStartFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: "Un enregistrement est déjà en cours."
        case .deviceSelectionFailed(let status): "Impossible de sélectionner le micro (erreur \(status))."
        case .invalidInputFormat: "Le micro ne fournit aucun signal (périphérique débranché ou accès refusé ?)."
        case .engineStartFailed(let error): "Le micro n'a pas pu démarrer : \(error.localizedDescription)"
        }
    }
}

/// Enregistre le micro et produit un `AudioClip` en 16 kHz mono.
///
/// Fonctionnement :
/// 1. `AVAudioEngine` lit le micro dans son format natif (souvent 48 kHz).
/// 2. Un « tap » sur le nœud d'entrée nous donne des petits tampons (~20 ms).
/// 3. Chaque tampon est converti en 16 kHz mono par `AVAudioConverter` et
///    ajouté au tableau d'échantillons.
///
/// On crée un moteur neuf à chaque enregistrement : c'est un peu plus lent
/// (quelques dizaines de ms), mais évite les états incohérents quand on
/// branche/débranche un micro entre deux dictées. Et surtout, le micro n'est
/// **jamais** ouvert en dehors d'une dictée (le voyant orange de macOS le prouve).
///
/// Les callbacks audio arrivent sur un thread temps réel : l'état partagé est
/// protégé par un verrou (`OSAllocatedUnfairLock`), d'où `@unchecked Sendable`.
public final class AudioRecorder: @unchecked Sendable {
    /// Niveau sonore normalisé (0…1), appelé ~20 fois par seconde sur un thread audio.
    public var onLevel: (@Sendable (Float) -> Void)?

    /// Appelé une fois, au premier tampon audio reçu, avec le délai écoulé depuis
    /// `start()`. C'est le vrai moment où l'on peut parler : avant, le micro
    /// n'enregistre pas encore (c'est ce qui coupe parfois la 1re syllabe).
    public var onReady: (@Sendable (TimeInterval) -> Void)?

    private var engine: AVAudioEngine?
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "audio")

    /// Format cible : 16 kHz, mono, Float32, non entrelacé.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioClip.sampleRate,
        channels: 1,
        interleaved: false
    )!

    public init() {}

    public var isRecording: Bool { engine != nil }

    /// Démarre l'enregistrement. `deviceUID == nil` → micro par défaut du système.
    public func start(deviceUID: String?) throws {
        guard engine == nil else { throw AudioRecorderError.alreadyRecording }
        samples.withLock { $0.removeAll(keepingCapacity: true) }

        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Choix du micro : on règle la propriété « périphérique courant » de
        // l'unité audio d'entrée, AVANT de lire son format.
        if let deviceUID, let deviceID = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var id = deviceID
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { throw AudioRecorderError.deviceSelectionFailed(status) }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.invalidInputFormat
        }

        let targetFormat = self.targetFormat
        let startedAt = Date()
        nonisolated(unsafe) var announcedReady = false
        // Le convertisseur est créé à partir du format RÉEL du premier tampon reçu
        // (et recréé s'il change) : juste après un changement de micro, le format
        // annoncé par le nœud peut encore être celui de l'ancien périphérique.
        // Le bloc du tap est toujours appelé sur le même thread audio, un par un :
        // cette variable n'est donc jamais accédée en parallèle.
        nonisolated(unsafe) var converter: AVAudioConverter?

        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            if !announcedReady {
                announcedReady = true
                self.onReady?(Date().timeIntervalSince(startedAt))
            }
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            }
            guard let converter else { return }

            // Taille du tampon de sortie : proportionnelle au rapport des fréquences.
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            // Le convertisseur « tire » ses données via ce bloc : on lui donne
            // notre tampon une fois, puis on dit qu'il n'y a plus rien pour l'instant.
            nonisolated(unsafe) var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error != nil { return }

            guard let channel = output.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            self.samples.withLock { $0.append(contentsOf: chunk) }

            // Niveaux pour la forme d'onde : un RMS par tranche de 50 ms.
            // (macOS livre souvent des tampons de 100 ms : sans ce découpage,
            // la forme d'onde serait saccadée.)
            if let onLevel = self.onLevel {
                let slice = 800 // 50 ms à 16 kHz
                var start = 0
                while start < chunk.count {
                    let end = min(start + slice, chunk.count)
                    var sum: Float = 0
                    for i in start..<end { sum += chunk[i] * chunk[i] }
                    let rms = (sum / Float(end - start)).squareRoot()
                    onLevel(min(1, rms * 8))
                    start = end
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error)
        }
        self.engine = engine
        logger.debug("Enregistrement démarré (\(inputFormat.sampleRate, privacy: .public) Hz, \(inputFormat.channelCount, privacy: .public) canaux)")
    }

    /// Arrête et renvoie l'audio capturé.
    public func stop() -> AudioClip {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        let captured = samples.withLock { buffer -> [Float] in
            defer { buffer.removeAll() }
            return buffer
        }
        return AudioClip(samples: captured)
    }

    /// Arrête et jette l'audio.
    public func cancel() {
        _ = stop()
    }
}
