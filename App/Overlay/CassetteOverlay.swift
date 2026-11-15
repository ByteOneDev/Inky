import SwiftUI

/// Dimensions du magnétoscope.
enum CassetteMetrics {
    /// Rangé : seule une languette dépasse du bord de l'écran.
    static let tab = CGSize(width: 22, height: 84)
    /// Sorti : la cassette entière.
    static let full = CGSize(width: 204, height: 124)
}

/// Style « magnétoscope » : une petite cassette rangée contre le bord de
/// l'écran. Au repos, une languette dépasse ; au survol ou pendant une dictée,
/// la cassette glisse hors du bord.
///
///     ┌──────────────────────────┐
///     │ ● INKY            0:07   │  ← étiquette : voyant + état
///     │ ┌──────────────────────┐ │
///     │ │  (✲)  ═══════  (✲)   │ │  ← bobines : tournent pendant la dictée,
///     │ └──────────────────────┘ │    rembobinent pendant la transcription
///     │ ▮▮▮▮▮▯▯▯▯▯          ⌃⌘   │  ← vu-mètre (ou touches ✕ ■ en mains libres)
///     └──────────────────────────┘
struct CassetteOverlay: View {
    let model: OverlayModel

    /// Coins arrondis seulement côté écran : l'autre côté « rentre » dans le bord.
    private var shape: UnevenRoundedRectangle {
        let r: CGFloat = 14
        return model.dockEdge == .right
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom),
                in: shape
            )
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
            .environment(\.colorScheme, .dark)
            .contentShape(shape)
            .onTapGesture { model.onClick?() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle where !model.isHovering:
            tab
        case .message(let text, let isError):
            HStack(spacing: 10) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? Color.yellow : Color.white)
                Text(text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
        default:
            deck
        }
    }

    // MARK: - Languette (rangé)

    private var tab: some View {
        VStack(spacing: 7) {
            Circle()
                .fill(Color.red.opacity(0.55))
                .frame(width: 5, height: 5)
            Reel(angle: .zero, size: 12)
            VStack(spacing: 2.5) {
                ForEach(0..<3) { _ in
                    Capsule().fill(.white.opacity(0.25)).frame(width: 8, height: 1.5)
                }
            }
        }
        // La languette est collée au bord : on décale le contenu côté écran.
        .offset(x: model.dockEdge == .right ? 1 : -1)
    }

    // MARK: - Cassette (sortie)

    private var deck: some View {
        VStack(spacing: 7) {
            label
            tapeWindow
            bottomRow
        }
        .padding(.vertical, 10)
        .padding(.leading, model.dockEdge == .right ? 12 : 8)
        .padding(.trailing, model.dockEdge == .right ? 8 : 12)
    }

    /// L'étiquette crème : voyant, nom, état.
    private var label: some View {
        HStack(spacing: 6) {
            StatusLED(phase: model.phase)
            Text("INKY")
                .font(.system(size: 11, weight: .bold, design: .serif))
                .tracking(1.2)
            Spacer(minLength: 4)
            status
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(Color(red: 0.16, green: 0.15, blue: 0.13))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color(red: 0.94, green: 0.91, blue: 0.83), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle: Text("Prêt")
        case .preparing: Text("Attends…")
        case .recording(_, let startedAt):
            if model.showsTimer {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                    Text(String(format: "REC %d:%02d", seconds / 60, seconds % 60))
                }
            } else {
                Text("REC")
            }
        case .transcribing: Text("Rembobinage…")
        case .rewriting(let name): Text("✦ \(name)")
        case .message: EmptyView()
        }
    }

    /// La fenêtre de la cassette, avec les deux bobines et la bande.
    private var tapeWindow: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reelSpeed == 0)) { context in
            let angle = Angle.degrees(context.date.timeIntervalSinceReferenceDate * reelSpeed * 360)
            HStack(spacing: 0) {
                Reel(angle: angle, size: 34, tape: 0.9)
                ZStack {
                    // La bande qui passe d'une bobine à l'autre.
                    Rectangle()
                        .fill(Color(red: 0.36, green: 0.24, blue: 0.15))
                        .frame(height: 3)
                        .offset(y: 13)
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(width: 30, height: 10)
                }
                .frame(maxWidth: .infinity)
                Reel(angle: angle, size: 34, tape: 0.55)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 46)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    /// Niveau du micro, seulement pendant l'enregistrement (sinon le vu-mètre est éteint).
    private var liveLevel: Float {
        guard case .recording = model.phase else { return 0 }
        return model.levels.suffix(3).max() ?? 0
    }

    /// Tours par seconde des bobines selon l'état (négatif = rembobinage).
    private var reelSpeed: Double {
        switch model.phase {
        case .recording: 0.5
        case .transcribing: -2.2
        case .rewriting: 1.0
        default: 0
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        HStack(spacing: 6) {
            switch model.phase {
            case .recording(true, _):
                DeckKey(symbol: "xmark", tint: .white) { model.onCancel?() }
                    .help("Annuler")
                VUMeter(level: liveLevel)
                DeckKey(symbol: "stop.fill", tint: .red) { model.onClick?() }
                    .help("Terminer et insérer")
            case .idle:
                Text("Clique ou maintiens \(model.shortcutLabel)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            default:
                VUMeter(level: liveLevel)
                Text(model.shortcutLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(height: 18)
    }
}

/// Une bobine : la bande enroulée (brune), le moyeu crème et ses rayons.
private struct Reel: View {
    let angle: Angle
    let size: CGFloat
    /// Part du diamètre occupée par la bande enroulée (0 = vide).
    var tape: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
            if tape > 0 {
                Circle()
                    .fill(Color(red: 0.33, green: 0.22, blue: 0.14))
                    .frame(width: size * tape, height: size * tape)
            }
            Circle()
                .fill(Color(red: 0.92, green: 0.89, blue: 0.81))
                .frame(width: size * 0.5, height: size * 0.5)
            ForEach(0..<3) { index in
                Capsule()
                    .fill(Color(white: 0.2))
                    .frame(width: max(1.5, size * 0.08), height: size * 0.42)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            Circle().fill(Color(white: 0.2)).frame(width: size * 0.14, height: size * 0.14)
        }
        .frame(width: size, height: size)
        .rotationEffect(angle)
    }
}

/// Voyant de l'étiquette : rouge qui clignote en enregistrement, ambre au
/// démarrage du micro, bleu pendant l'IA, vert pendant la transcription.
private struct StatusLED: View {
    let phase: OverlayModel.Phase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let blinkOn = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(isRecording && !blinkOn ? 0.3 : 1)
                .shadow(color: color.opacity(0.8), radius: isLit ? 3 : 0)
        }
    }

    private var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    private var isLit: Bool { phase != .idle }

    private var color: Color {
        switch phase {
        case .recording: .red
        case .preparing: .orange
        case .transcribing: .green
        case .rewriting: .cyan
        default: Color(white: 0.55)
        }
    }
}

/// Vu-mètre à segments : vert, puis jaune, puis rouge.
private struct VUMeter: View {
    let level: Float
    private let segments = 10

    var body: some View {
        // Racine carrée : rend visibles les sons faibles.
        let lit = Int((Double(sqrt(max(0, level))) * 1.6 * Double(segments)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(index).opacity(index < lit ? 1 : 0.18))
                    .frame(width: 5, height: 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.linear(duration: 0.08), value: lit)
    }

    private func color(_ index: Int) -> Color {
        index < 6 ? .green : (index < 8 ? .yellow : .red)
    }
}

/// Touche de magnétoscope (mains libres : ✕ annuler, ■ terminer).
private struct DeckKey: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 26, height: 17)
                .background(
                    LinearGradient(colors: [Color(white: 0.42), Color(white: 0.28)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
