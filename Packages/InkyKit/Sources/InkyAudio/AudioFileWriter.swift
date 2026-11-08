@preconcurrency import AVFoundation
import Foundation
import InkyCore

/// Écrit un `AudioClip` sur le disque, compressé en AAC (.m4a).
///
/// 16 kHz mono en AAC à 32 kbit/s ≈ 4 Ko par seconde : une dictée de 10 s
/// pèse ~40 Ko, contre ~320 Ko en WAV non compressé.
public enum AudioFileWriter {
    public static func writeM4A(_ clip: AudioClip, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioClip.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        // `commonFormat` = format des tampons qu'on fournit (Float32), le
        // fichier, lui, est encodé selon `settings`.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(clip.samples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(clip.samples.count)
        clip.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: clip.samples.count)
        }
        try file.write(from: buffer)
    }

    /// Relit un fichier audio en 16 kHz mono (pour réécouter ou retranscrire).
    public static func read(_ url: URL) throws -> AudioClip {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return AudioClip(samples: [])
        }
        try file.read(into: buffer)
        let data = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        return AudioClip(samples: Array(data))
    }
}
