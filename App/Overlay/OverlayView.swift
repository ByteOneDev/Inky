import SwiftUI

/// Le contenu de la pastille : une capsule noire, sobre, qui change de taille
/// selon l'état (style « Wispr Flow »).
///
///     repos        ▬            (survol : « Clique ou maintiens ⌃⌘ pour dicter »)
///     préparation  ⦙⦙⦙ Attends…  (barres grises : ne parle pas encore)
///     dictée       ● ıllıılı 0:07 (barres blanches : parle !)  [mains libres : ✕ … ■]
///     transcription • • •
///     IA           ✦ Rédaction…
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        switch model.style {
        case .capsule: CapsuleOverlay(model: model)
        case .cassette: CassetteOverlay(model: model)
        case .radio: RadioOverlay(model: model)
        }
    }
}

/// Style « capsule ».
private struct CapsuleOverlay: View {
    let model: OverlayModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(model.phase.isCompact && !model.isHovering ? 0.7 : 0.88), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
            .padding(2)
            .environment(\.colorScheme, .dark)
            .contentShape(Capsule())
            .onTapGesture { model.onClick?() }
            .animation(.easeOut(duration: 0.15), value: model.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if model.isHovering {
                Text(model.hint)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
            } else {
                // Pas `EmptyView` : elle ne dessinerait même pas le fond de la capsule.
                Color.clear
            }

        case .preparing:
            HStack(spacing: 8) {
                WaveformView(levels: Array(repeating: 0, count: 9), color: .white.opacity(0.35))
                    .frame(width: 44)
                Text("Attends…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 14)

        case .recording(let handsFree, let startedAt):
            HStack(spacing: 8) {
                if handsFree {
                    CircleButton(symbol: "xmark", background: .white.opacity(0.18)) { model.onCancel?() }
                        .help("Annuler")
                } else {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                }
                WaveformView(levels: model.levels, color: .white)
                if model.showsTimer {
                    ElapsedTimeView(since: startedAt)
                }
                if handsFree {
                    CircleButton(symbol: "stop.fill", background: .red) { model.onClick?() }
                        .help("Terminer et insérer")
                }
            }
            .padding(.horizontal, handsFree ? 6 : 14)

        case .transcribing:
            PulsingDots()

        case .rewriting(let name):
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                PulsingDots(size: 3.5)
                    .frame(width: 22)
            }
            .padding(.horizontal, 14)

        case .message(let text, let isError):
            HStack(spacing: 8) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? Color.yellow : Color.white)
                Text(text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Petit bouton rond de la pastille mains libres (annuler, terminer).
private struct CircleButton: View {
    let symbol: String
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Chronomètre « 0:07 », rafraîchi chaque seconde.
private struct ElapsedTimeView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Trois points qui « respirent » l'un après l'autre (transcription en cours).
private struct PulsingDots: View {
    var size: CGFloat = 5

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.9) {
                ForEach(0..<3) { index in
                    // Une sinusoïde décalée pour chaque point : effet de vague.
                    let wave = (sin(t * 5 - Double(index) * 0.8) + 1) / 2
                    Circle()
                        .fill(.white.opacity(0.35 + 0.6 * wave))
                        .frame(width: size, height: size)
                        .offset(y: -1.5 * wave)
                }
            }
        }
    }
}

/// Barres verticales dont la hauteur suit le niveau du micro.
struct WaveformView: View {
    let levels: [Float]
    var color: Color = .white

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: barHeight(levels[index]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.linear(duration: 0.08), value: levels)
    }

    private func barHeight(_ level: Float) -> CGFloat {
        // Racine carrée : rend visibles les sons faibles sans écraser les forts.
        3 + CGFloat(sqrt(level)) * 18
    }
}
