import Observation
import SwiftUI

/// Les pages de la fenêtre principale.
enum MainSection: String, CaseIterable, Identifiable {
    case home, history, dictionary, snippets, templates, style
    case general, audio, transcription, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .history: "Historique"
        case .dictionary: "Dictionnaire"
        case .snippets: "Snippets"
        case .templates: "Prompts IA"
        case .style: "Style"
        case .general: "Général"
        case .audio: "Audio"
        case .transcription: "Transcription"
        case .about: "À propos"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .dictionary: "character.book.closed"
        case .snippets: "text.quote"
        case .templates: "sparkles"
        case .style: "textformat"
        case .general: "gearshape"
        case .audio: "mic"
        case .transcription: "waveform"
        case .about: "info.circle"
        }
    }

    static let main: [MainSection] = [.home, .history, .dictionary, .snippets, .templates, .style]
    static let settings: [MainSection] = [.general, .audio, .transcription, .about]
}

/// Page affichée dans la fenêtre principale (partagée avec le menu, qui peut
/// ouvrir directement « Réglages » ou « Historique »).
@MainActor
@Observable
final class MainNavigation {
    var section: MainSection = .home
}

/// La fenêtre principale : barre latérale à gauche, page à droite.
struct MainWindowView: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(app: app)
                .frame(width: 214)
            Divider()
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Theme.page)
        .ignoresSafeArea(.container, edges: .top)
        // Interface en français : jours de la semaine, dates, nombres.
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    @ViewBuilder
    private var page: some View {
        switch app.navigation.section {
        case .home: HomeView(app: app)
        case .history: HistoryPage(app: app)
        case .dictionary: DictionaryPage(vocabulary: app.vocabulary)
        case .snippets: SnippetsPage(vocabulary: app.vocabulary)
        case .templates: TemplatesPage(app: app)
        case .style: StylePage(settings: app.settings)
        case .general: GeneralSettings(app: app)
        case .audio: AudioSettings(settings: app.settings, controller: app.controller)
        case .transcription: ModelSettings(app: app)
        case .about: AboutView(app: app)
        }
    }
}

private struct Sidebar: View {
    let app: AppModel

    var body: some View {
        @Bindable var navigation = app.navigation
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: 2) {
            // Logo (sous les boutons de fenêtre, la barre de titre est transparente).
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Inky").font(Theme.title(24))
            }
            .padding(.horizontal, 10)
            .padding(.top, 46)
            .padding(.bottom, 16)

            ForEach(MainSection.main) { item(for: $0) }

            Spacer(minLength: 18)

            SectionLabel(text: "Réglages").padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(MainSection.settings) { item(for: $0) }

            StatusFooter(app: app)
                .padding(.top, 14)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    private func item(for section: MainSection) -> some View {
        let selected = app.navigation.section == section
        return Button {
            app.navigation.section = section
        } label: {
            Label(section.title, systemImage: section.icon)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// En bas de la barre latérale : l'état d'Inky et l'interrupteur général.
private struct StatusFooter: View {
    let app: AppModel

    var body: some View {
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Toggle("Inky activé", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusText: String {
        if !app.settings.isEnabled { return "En pause" }
        switch app.controller.modelStatus {
        case .ready: return app.controller.hotkeysActive ? "Prêt à dicter" : "Accessibilité requise"
        case .loading: return "Chargement du modèle…"
        case .notInstalled: return "Aucun modèle installé"
        case .failed: return "Erreur du modèle"
        }
    }

    private var statusColor: Color {
        guard app.settings.isEnabled else { return .secondary }
        if case .ready = app.controller.modelStatus, app.controller.hotkeysActive { return .green }
        return .orange
    }
}
