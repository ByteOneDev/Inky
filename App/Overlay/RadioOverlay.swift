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

    /// Boîtier clair (biseau plus marqué).
    var isLight: Bool { self == .aluminium || self == .cream }

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
        let shape = dockedShape(model.dockEdge, radius: 18)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: finish.body, startPoint: .top, endPoint: .bottom), in: shape)
            // Biseau clair juste à l'intérieur, puis la **bordure noire** épaisse
            // qui détoure l'appareil sur n'importe quel fond.
            .overlay(shape.inset(by: 3).stroke(.white.opacity(finish.isLight ? 0.55 : 0.12), lineWidth: 1))
            .overlay(shape.strokeBorder(Color.black, lineWidth: 3))
            .contentShape(shape)
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
                SpeakerGrille(color: finish.grille, columns: 9, rows: 9, dot: 4)
                    .frame(width: 64, height: 64)
                Screen(finish: finish) { screenContent }
            }
            .padding(.vertical, 12)
            .padding(.leading, model.dockEdge == .right ? 15 : 11)
            .padding(.trailing, model.dockEdge == .right ? 11 : 15)
        }
    }

    /// L'écran : la vague en pointillés en haut, une barre noire d'état en bas.
    private var screenContent: some View {
        VStack(spacing: 0) {
            wave
                .padding(.horizontal, 3)
                .padding(.top, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 5) {
                statusBar
            }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 21)
            .background(Color.black.opacity(0.85))
        }
    }

    /// La vague suit la voix pendant l'enregistrement ; ailleurs, une houle
    /// calme (pâle pendant « Attends… », vive pendant la transcription).
    @ViewBuilder
    private var wave: some View {
        switch model.phase {
        case .recording:
            DitherWave(levels: model.levels, color: finish.screen)
        case .preparing:
            DitherWave(levels: [0, 0], color: finish.screen.opacity(0.4), floor: 0.08)
        case .transcribing, .rewriting:
            DitherWave(levels: [0.12, 0.2, 0.12], color: finish.screen, floor: 0.18)
        default:
            DitherWave(levels: [0, 0], color: finish.screen.opacity(0.7), floor: 0.1)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch model.phase {
        case .recording(let handsFree, _):
            if handsFree {
                ScreenButton(symbol: "xmark", color: .white) { model.onCancel?() }.help("Annuler")
            }
            status
            Spacer(minLength: 0)
            if handsFree {
                ScreenButton(symbol: "stop.fill", color: .red) { model.onClick?() }.help("Terminer et insérer")
            }
        case .idle:
            Text("Clique ou \(model.shortcutLabel)")
        default:
            status
        }
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
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color(white: 0.12), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(Glare().allowsHitTesting(false))
            .clipShape(shape)
            // Cadre noir épais autour de l'écran.
            .overlay(shape.strokeBorder(Color.black, lineWidth: 2.5))
    }
}

/// Reflet de vitre : une bande claire en diagonale, en haut à droite de l'écran.
private struct Glare: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.55, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: h * 0.5))
                path.addQuadCurve(to: CGPoint(x: w * 0.55, y: 0), control: CGPoint(x: w * 0.82, y: h * 0.22))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0)], startPoint: .topTrailing, endPoint: .bottomLeading))
            .blur(radius: 1.5)
        }
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
                    // Coins coupés : la grille forme un carré aux angles arrondis.
                    let cx = abs(Double(column) - Double(columns - 1) / 2) / (Double(columns) / 2)
                    let cy = abs(Double(row) - Double(rows - 1) / 2) / (Double(rows) / 2)
                    if columns > 3, pow(cx, 4) + pow(cy, 4) > 0.95 { continue }
                    let center = CGPoint(x: dx * (CGFloat(column) + 0.5), y: dy * (CGFloat(row) + 0.5))
                    let rect = CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
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
