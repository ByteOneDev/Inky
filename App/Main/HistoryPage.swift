import AVFoundation
import InkyStorage
import SwiftUI

/// Historique des dictées, regroupées par jour, avec recherche, réécoute et
/// réglages de conservation.
struct HistoryPage: View {
    let app: AppModel

    @State private var entries: [HistoryEntry] = []
    @State private var search = ""
    @State private var observation: HistoryObservation?
    @State private var player: AVAudioPlayer?
    @State private var confirmClear = false
    @State private var confirmResetStats = false

    var body: some View {
        @Bindable var settings = app.settings
        Page(title: "Historique", subtitle: "Tes dictées restent sur ce Mac. Survole une ligne pour la copier, la réécouter ou la supprimer.") {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher dans l'historique", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))

            if app.controller.history == nil {
                Card { Label("La base de l'historique n'a pas pu être ouverte.", systemImage: "exclamationmark.triangle") }
            } else if entries.isEmpty {
                Card {
                    Text(search.isEmpty ? (settings.historyRetention == .never ? "L'historique est désactivé." : "Aucune dictée pour l'instant.") : "Aucun résultat pour « \(search) ».")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedByDay, id: \.day) { group in
                    SectionLabel(text: Self.dayLabel(group.day)).padding(.top, 4)
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 90) }
                                HistoryLine(
                                    entry: entry,
                                    onPlay: app.controller.history?.audioURL(for: entry).map { url in { play(url) } },
                                    onDelete: { try? app.controller.history?.delete(entry) }
                                )
                            }
                        }
                    }
                }
            }

            SectionLabel(text: "Conservation et confidentialité").padding(.top, 10)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Supprimer automatiquement après", selection: $settings.historyRetention) {
                        ForEach(HistoryRetention.allCases) { Text($0.displayName).tag($0) }
                    }
                    .frame(maxWidth: 380)
                    Toggle("Conserver aussi l'audio (≈ 4 Ko par seconde, pour réécouter)", isOn: $settings.keepAudio)
                    Toggle("Compter les mots dictés pour les statistiques de l'accueil", isOn: $settings.collectStats)
                    Text("Les statistiques ne gardent que des nombres (mots, durée, nom de l'app), jamais le texte. Elles survivent à la suppression de l'historique.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Effacer tout l'historique…", role: .destructive) { confirmClear = true }
                        Button("Remettre les statistiques à zéro…") { confirmResetStats = true }
                    }
                    .disabled(app.controller.history == nil)
                }
            }
        }
        .onAppear(perform: startObserving)
        .onChange(of: search) { startObserving() }
        .onDisappear { observation = nil; player?.stop() }
        .confirmationDialog("Effacer tout l'historique ?", isPresented: $confirmClear) {
            Button("Tout effacer", role: .destructive) { try? app.controller.history?.deleteAll() }
        } message: {
            Text("Les textes et les fichiers audio seront supprimés définitivement. Les statistiques sont conservées.")
        }
        .confirmationDialog("Remettre les statistiques à zéro ?", isPresented: $confirmResetStats) {
            Button("Remettre à zéro", role: .destructive) { try? app.controller.history?.resetUsage() }
        } message: {
            Text("Mots dictés, série et temps gagné repartiront de zéro. L'historique n'est pas touché.")
        }
    }

    private var groupedByDay: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.createdAt > $1.createdAt }) }
    }

    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func startObserving() {
        observation = app.controller.history?.observe(search: search) { entries = $0 }
    }

    private func play(_ url: URL) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// Une dictée : l'heure à gauche, le texte à droite, les actions au survol.
struct HistoryLine: View {
    let entry: HistoryEntry
    /// Afficher aussi le jour (page d'accueil, où les dictées ne sont pas groupées).
    var showsDay = false
    var onPlay: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if showsDay {
                    Text(HistoryPage.dayLabel(Calendar.current.startOfDay(for: entry.createdAt)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .textSelection(.enabled)
                    .lineLimit(hovering ? nil : 3)
                HStack(spacing: 6) {
                    if let app = entry.appName { Text(app) }
                    Text("· \(entry.audioDuration, format: .number.precision(.fractionLength(1))) s")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if let onPlay {
                    iconButton("play.circle", help: "Réécouter", action: onPlay)
                }
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copier", action: copy)
                if let onDelete {
                    iconButton("trash", help: "Supprimer", action: onDelete)
                }
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copier", action: copy)
            if let onDelete { Button("Supprimer", role: .destructive, action: onDelete) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}
