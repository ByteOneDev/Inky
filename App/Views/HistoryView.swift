import AVFoundation
import InkyStorage
import SwiftUI

/// Liste des dictées passées : recherche, copie, réécoute, suppression.
struct HistoryView: View {
    let app: AppModel

    @State private var entries: [HistoryEntry] = []
    @State private var search = ""
    @State private var observation: HistoryObservation?
    @State private var selection: HistoryEntry.ID?
    @State private var player: AVAudioPlayer?

    var body: some View {
        Group {
            if app.controller.history == nil {
                ContentUnavailableView("Historique indisponible", systemImage: "exclamationmark.triangle", description: Text("La base de données n'a pas pu être ouverte."))
            } else if entries.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "Aucune dictée pour l'instant" : "Aucun résultat",
                    systemImage: "text.bubble",
                    description: Text(search.isEmpty ? "Tes dictées apparaîtront ici." : "Essaie un autre mot.")
                )
            } else {
                List(entries, selection: $selection) { entry in
                    HistoryRow(entry: entry, onCopy: { copy(entry) }, onPlay: audioURL(entry).map { url in { play(url) } }, onDelete: { delete(entry) })
                }
            }
        }
        .searchable(text: $search, prompt: "Rechercher dans l'historique")
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { startObserving() }
        .onChange(of: search) { startObserving() }
        .onDisappear { observation = nil; player?.stop() }
    }

    /// (Re)lance l'observation de la base : la liste se met à jour toute seule
    /// quand une nouvelle dictée est enregistrée.
    private func startObserving() {
        observation = app.controller.history?.observe(search: search) { entries = $0 }
    }

    private func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    private func delete(_ entry: HistoryEntry) {
        try? app.controller.history?.delete(entry)
    }

    private func audioURL(_ entry: HistoryEntry) -> URL? {
        app.controller.history?.audioURL(for: entry)
    }

    private func play(_ url: URL) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void
    let onPlay: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .textSelection(.enabled)
                    .lineLimit(4)
                HStack(spacing: 6) {
                    Text(entry.createdAt, format: .dateTime.day().month().hour().minute())
                    if let app = entry.appName { Text("· \(app)") }
                    Text("· \(entry.audioDuration, format: .number.precision(.fractionLength(1))) s")
                    Text("· transcrit en \(entry.processingTime, format: .number.precision(.fractionLength(2))) s")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                if let onPlay {
                    Button(action: onPlay) { Image(systemName: "play.circle") }.help("Réécouter")
                }
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }.help("Copier")
                Button(action: onDelete) { Image(systemName: "trash") }.help("Supprimer")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copier", action: onCopy)
            Button("Supprimer", role: .destructive, action: onDelete)
        }
    }
}
