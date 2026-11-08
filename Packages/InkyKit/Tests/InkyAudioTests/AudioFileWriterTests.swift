import Foundation
import InkyCore
import Testing
@testable import InkyAudio

struct AudioFileWriterTests {
    @Test func roundTripM4A() throws {
        // 10 s de sinusoïde à 440 Hz.
        let samples = (0..<160_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 16_000)) * 0.5 }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        try AudioFileWriter.writeM4A(AudioClip(samples: samples), to: url)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        // En WAV 16 bits, 10 s pèseraient 320 Ko. L'AAC a un en-tête fixe
        // (~25 Ko) puis ne coûte que quelques Ko par seconde.
        #expect(size > 1_000 && size < 100_000, "taille : \(size)")

        let back = try AudioFileWriter.read(url)
        #expect(abs(back.duration - 10.0) < 0.2)
        #expect(back.rms > 0.2)
    }
}
