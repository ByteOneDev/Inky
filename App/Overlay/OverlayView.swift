import SwiftUI

/// Le contenu de la pastille.
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        Group {
            if model.phase.isCompact {
                compact
            } else {
                full
            }
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Capsule())
        .onTapGesture { model.onClick?() }
    }

    /// Au repos : une petite capsule avec trois points.
    private var compact: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { _ in
                Circle().fill(.white.opacity(0.75)).frame(width: 3, height: 3)
            }
        }
        .frame(width: OverlayController.compactSize.width, height: OverlayController.compactSize.height)
        .background(.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .help(model.hint)
    }

    private var full: some View {
        HStack(spacing: 10) {
            indicator
            content
            if case .recording(_, let startedAt) = model.phase, model.showsTimer {
                ElapsedTimeView(since: startedAt)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: OverlayController.fullSize.width - 4, height: OverlayController.fullSize.height - 4)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .frame(width: OverlayController.fullSize.width, height: OverlayController.fullSize.height)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .preparing:
            Circle().fill(Color.yellow).frame(width: 8, height: 8)
        case .recording(let handsFree, _):
            Circle()
                .fill(handsFree ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
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
        case .idle:
            EmptyView()
        case .preparing:
            label("Attends…")
        case .recording:
            WaveformView(levels: model.levels)
        case .transcribing:
            label("Transcription…")
        case .message(let text, _):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chronomètre « 0:07 », rafraîchi chaque seconde.
private struct ElapsedTimeView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
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
        3 + CGFloat(sqrt(level)) * 20
    }
}
