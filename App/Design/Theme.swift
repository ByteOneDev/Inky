import AppKit
import SwiftUI

/// L'identité visuelle d'Inky : un papier crème, une encre bleu nuit, des
/// titres à empattements (police « New York » du système), des cartes
/// arrondies. Chaque couleur a une variante claire et une variante sombre.
enum Theme {
    /// Fond des pages.
    static let page = dynamic(light: 0xFAF8F4, dark: 0x1D1C1A)
    /// Fond de la barre latérale.
    static let sidebar = dynamic(light: 0xF1EEE7, dark: 0x242320)
    /// Fond des cartes.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2B2A27)
    /// Élément sélectionné dans la barre latérale.
    static let selection = dynamic(light: 0xE4E0D6, dark: 0x37352F)
    /// Couleur d'accent : l'encre.
    static let ink = dynamic(light: 0x2E3A8C, dark: 0x9AA4F5)
    /// Bordure discrète des cartes.
    static let border = Color.primary.opacity(0.08)

    /// Titre de page, à empattements.
    static func title(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// Crée une couleur qui suit le mode clair / sombre du système.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Composants réutilisables

/// Une page de la fenêtre principale : titre à empattements, sous-titre,
/// contenu défilant sur fond crème.
struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.title())
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Une page de réglages : même en-tête, puis un formulaire macOS standard
/// (sections groupées) qui se fond dans le fond crème.
struct FormPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 36)
                .padding(.top, 34)
                .padding(.bottom, 4)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.page)
    }
}

/// Carte blanche arrondie.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
    }
}

/// Petit titre de section en capitales (« AUJOURD'HUI »).
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Pastille d'information : icône + valeur + légende.
struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = Theme.ink

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
