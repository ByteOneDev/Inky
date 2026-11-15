import SwiftUI

/// Galerie de choix de la pastille : un aperçu vivant de chaque style (et de
/// chaque finition de la radio). Clic = choisir.
struct OverlayStyleGallery: View {
    @Bindable var settings: AppSettings

    /// Un choix possible : un style, et une finition pour la radio.
    private struct Option: Identifiable {
        let style: OverlayStyle
        let finish: RadioFinish?
        var id: String { style.rawValue + (finish?.rawValue ?? "") }
        var name: String { finish.map { "Radio \($0.displayName.lowercased())" } ?? style.displayName }
    }

    private let options: [Option] =
        [Option(style: .capsule, finish: nil), Option(style: .cassette, finish: nil)]
        + RadioFinish.allCases.map { Option(style: .radio, finish: $0) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(options) { option in
                let selected = isSelected(option)
                Button {
                    settings.overlayStyle = option.style
                    if let finish = option.finish { settings.overlayFinish = finish }
                } label: {
                    VStack(spacing: 8) {
                        preview(option)
                            .frame(maxWidth: .infinity)
                            .frame(height: 92)
                            .background(
                                LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(option.name)
                            .font(.callout.weight(selected ? .semibold : .regular))
                    }
                    .padding(8)
                    .background(selected ? Theme.ink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Theme.ink : Theme.border, lineWidth: selected ? 2 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelected(_ option: Option) -> Bool {
        settings.overlayStyle == option.style && (option.finish == nil || option.finish == settings.overlayFinish)
    }

    /// Le vrai rendu de la pastille, en train d'enregistrer, réduit.
    private func preview(_ option: Option) -> some View {
        let model = OverlayModel.preview(style: option.style, finish: option.finish ?? .graphite)
        let phase = model.phase
        let size = OverlayController.size(for: phase, style: option.style, hovering: false, showsTimer: true)
        let scale: CGFloat = option.style == .capsule ? 0.6 : 0.62
        // `scaleEffect` ne change que le dessin : on redonne ensuite la taille
        // réduite à la mise en page, sinon l'aperçu déborde de sa carte.
        return OverlayView(model: model)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .allowsHitTesting(false)
    }
}

extension OverlayModel {
    /// Modèle figé pour les aperçus : enregistrement en cours, niveaux fictifs.
    static func preview(style: OverlayStyle, finish: RadioFinish) -> OverlayModel {
        let model = OverlayModel()
        model.style = style
        model.finish = finish
        model.dockEdge = .right
        model.shortcutLabel = "⌃⌘"
        model.phase = .recording(handsFree: false, startedAt: Date().addingTimeInterval(-7))
        model.levels = (0..<barCount).map { index in
            Float(0.08 + 0.35 * abs(sin(Double(index) * 0.9)))
        }
        return model
    }
}
