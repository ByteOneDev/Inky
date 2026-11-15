import SwiftUI

/// Finition de la radio : couleur du boîtier et de l'écran.
enum RadioFinish: String, Codable, CaseIterable, Identifiable {
    case aluminium, graphite, ink, cream

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aluminium: "Aluminium"
        case .graphite: "Graphite"
        case .ink: "Encre"
        case .cream: "Crème"
        }
    }

    /// Dégradé du boîtier (haut → bas).
    var body: [Color] {
        switch self {
        case .aluminium: [Color(white: 0.88), Color(white: 0.66)]
        case .graphite: [Color(white: 0.27), Color(white: 0.12)]
        case .ink: [Color(red: 0.20, green: 0.25, blue: 0.58), Color(red: 0.10, green: 0.13, blue: 0.35)]
        case .cream: [Color(red: 0.96, green: 0.93, blue: 0.85), Color(red: 0.84, green: 0.78, blue: 0.66)]
        }
    }

    /// Couleur des trous du haut-parleur.
    var grille: Color {
        switch self {
        case .aluminium, .cream: .black.opacity(0.55)
        case .graphite: .black.opacity(0.8)
        case .ink: Color(red: 0.04, green: 0.06, blue: 0.2).opacity(0.9)
        }
    }

    /// Couleur « phosphore » de l'écran.
    var screen: Color {
        switch self {
        case .aluminium: Color(red: 1.0, green: 0.68, blue: 0.25)   // ambre
        case .graphite: Color(red: 0.45, green: 1.0, blue: 0.55)    // vert
        case .ink: Color(red: 0.62, green: 0.78, blue: 1.0)         // bleu glacier
        case .cream: Color(red: 1.0, green: 0.45, blue: 0.32)       // corail
        }
    }

    /// Bordure du boîtier.
    var bezel: Color {
        switch self {
        case .aluminium, .cream: .black.opacity(0.25)
        case .graphite, .ink: .white.opacity(0.16)
        }
    }
}

enum RadioMetrics {
    static let tab = CGSize(width: 22, height: 84)
    static let full = CGSize(width: 214, height: 104)
}

/// Style « radio » : un petit poste rangé contre le bord de l'écran, avec une
/// grille de haut-parleur et un écran qui affiche la voix.
///
///     ┌────────────────────────────┐
///     │ ⠿⠿⠿⠿⠿⠿  ┌───────────────┐ │
///     │ ⠿⠿⠿⠿⠿⠿  │ ● REC   0:07  │ │  ← état
///     │ ⠿⠿⠿⠿⠿⠿  │ ▁▃▆█▅▂▁▃▅▇▄▂  │ │  ← forme d'onde (ou ✕ … ■ en mains libres)
///     │ ⠿⠿⠿⠿⠿⠿  └───────────────┘ │
///     └────────────────────────────┘
struct RadioOverlay: View {
    let model: OverlayModel

    private var finish: RadioFinish { model.finish }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: finish.body, startPoint: .top, endPoint: .bottom), in: dockedShape(model.dockEdge, radius: 18))
            .overlay(dockedShape(model.dockEdge, radius: 18).strokeBorder(finish.bezel, lineWidth: 1))
            .contentShape(dockedShape(model.dockEdge, radius: 18))
            .onTapGesture { model.onClick?() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle where !model.isHovering:
            // Rangé : une languette avec un peu de grille et le voyant.
            VStack(spacing: 8) {
                Circle().fill(finish.screen.opacity(0.7)).frame(width: 5, height: 5)
                SpeakerGrille(color: finish.grille, columns: 2, rows: 6, dot: 3.2)
                    .frame(width: 10, height: 34)
            }
            .offset(x: model.dockEdge == .right ? 1 : -1)
        case .message(let text, let isError):
            Screen(finish: finish) {
                HStack(spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    Text(text).lineLimit(3).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isError ? Color.yellow : finish.screen)
                .padding(.horizontal, 10)
            }
            .padding(9)
        default:
            HStack(spacing: 10) {
                SpeakerGrille(color: finish.grille, columns: 7, rows: 7, dot: 4.4)
                    .frame(width: 66, height: 66)
                Screen(finish: finish) { screenContent }
            }
            .padding(.vertical, 12)
            .padding(.leading, model.dockEdge == .right ? 14 : 10)
            .padding(.trailing, model.dockEdge == .right ? 10 : 14)
        }
    }

    private var screenContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                status
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(finish.screen)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            bottom
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle: Text("INKY · PRÊT")
        case .preparing: Text("ATTENDS…")
        case .recording(_, let startedAt):
            Circle().fill(Color.red).frame(width: 6, height: 6)
            if model.showsTimer {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                    Text(String(format: "REC %d:%02d", seconds / 60, seconds % 60))
                }
            } else {
                Text("REC")
            }
        case .transcribing: Text("TRANSCRIPTION")
        case .rewriting(let name): Text("✦ \(name)")
        case .message: EmptyView()
        }
    }

    @ViewBuilder
    private var bottom: some View {
        switch model.phase {
        case .idle:
            Text("Clique ou maintiens \(model.shortcutLabel)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(finish.screen.opacity(0.8))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .recording(let handsFree, _):
            HStack(spacing: 5) {
                if handsFree {
                    ScreenButton(symbol: "xmark", color: finish.screen) { model.onCancel?() }.help("Annuler")
                }
                ScreenWaveform(levels: model.levels, color: finish.screen)
                if handsFree {
                    ScreenButton(symbol: "stop.fill", color: .red) { model.onClick?() }.help("Terminer et insérer")
                }
            }
        case .preparing:
            ScreenWaveform(levels: Array(repeating: 0, count: 16), color: finish.screen.opacity(0.35))
        default:
            ScanLine(color: finish.screen)
        }
    }
}

/// Coins arrondis seulement côté écran : l'autre côté « rentre » dans le bord.
func dockedShape(_ edge: DockEdge, radius r: CGFloat) -> UnevenRoundedRectangle {
    edge == .right
        ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
}

/// Écran sombre et légèrement bombé.
private struct Screen<Content: View>: View {
    let finish: RadioFinish
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color(white: 0.13), Color(white: 0.04)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                // Reflet en haut de l'écran.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.black.opacity(0.6), lineWidth: 1.5))
    }
}

/// Grille de haut-parleur : des trous ronds alignés, dessinés avec `Canvas`
/// (plus léger qu'une vue par trou).
private struct SpeakerGrille: View {
    let color: Color
    let columns: Int
    let rows: Int
    let dot: CGFloat

    var body: some View {
        Canvas { context, size in
            let dx = size.width / CGFloat(columns)
            let dy = size.height / CGFloat(rows)
            for column in 0..<columns {
                for row in 0..<rows {
                    let center = CGPoint(x: dx * (CGFloat(column) + 0.5), y: dy * (CGFloat(row) + 0.5))
                    let rect = CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

/// Forme d'onde « phosphore » : barres symétriques autour du centre.
private struct ScreenWaveform: View {
    let levels: [Float]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(height: max(2, proxy.size.height * CGFloat(min(1, sqrt(levels[index]) * 1.3))))
                }
            }
            .frame(maxHeight: .infinity)
            .shadow(color: color.opacity(0.6), radius: 3)
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}

/// Une ligne lumineuse qui balaie l'écran (transcription, IA).
private struct ScanLine: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let x = (sin(t * 3) + 1) / 2 * (proxy.size.width - 18)
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 3)
                    Capsule().fill(color).frame(width: 18, height: 3)
                        .shadow(color: color, radius: 4)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct ScreenButton: View {
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
