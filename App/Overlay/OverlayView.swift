import SwiftUI

/// Le contenu de la pastille : une capsule sombre avec la forme d'onde.
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            indicator
            content
        }
        .padding(.horizontal, 16)
        .frame(width: 220, height: 48)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .padding(4)
        .frame(width: 220, height: 48)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.phase {
        case .recording(let handsFree):
            Circle()
                .fill(handsFree ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
                .help(handsFree ? "Mains libres" : "Push-to-talk")
        case .transcribing:
            ProgressView().controlSize(.small)
        case .message(_, let isError):
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? .yellow : .white)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .recording:
            WaveformView(levels: model.levels)
        case .transcribing:
            Text("Transcription…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .message(let text, _):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Barres verticales dont la hauteur suit le niveau du micro.
struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(levels[index]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.linear(duration: 0.08), value: levels)
    }

    private func barHeight(_ level: Float) -> CGFloat {
        // Racine carrée : rend visibles les sons faibles sans écraser les forts.
        3 + CGFloat(sqrt(level)) * 22
    }
}
