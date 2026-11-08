import Foundation

/// Un enregistrement audio prêt à être transcrit.
///
/// Whisper attend toujours le même format : **16 000 échantillons par seconde,
/// mono, nombres flottants entre -1 et 1**. `InkyAudio` se charge de convertir
/// le micro (souvent 48 kHz stéréo) vers ce format pendant l'enregistrement.
public struct AudioClip: Sendable, Equatable {
    /// Fréquence d'échantillonnage imposée par Whisper.
    public static let sampleRate: Double = 16_000

    /// Les échantillons bruts, 16 kHz mono.
    public let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }

    /// Durée en secondes (nombre d'échantillons ÷ échantillons par seconde).
    public var duration: TimeInterval {
        Double(samples.count) / Self.sampleRate
    }

    /// Niveau « RMS » (root mean square) : la puissance moyenne du signal.
    /// Sert à repérer un enregistrement quasi silencieux, sur lequel Whisper a
    /// tendance à « halluciner » du texte qui n'a jamais été prononcé.
    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Valeur absolue maximale (le « pic »).
    public var peak: Float {
        samples.reduce(0) { max($0, abs($1)) }
    }
}
