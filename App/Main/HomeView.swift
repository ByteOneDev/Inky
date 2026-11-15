import Charts
import InkyCore
import InkyStorage
import SwiftUI

/// Page d'accueil : statistiques d'utilisation et dernières dictées.
///
/// Les chiffres viennent de la table `usage` (des nombres, jamais de texte) et
/// se mettent à jour en direct grâce à l'observation de la base.
struct HomeView: View {
    let app: AppModel

    @State private var summary = UsageSummary()
    @State private var recent: [HistoryEntry] = []
    @State private var usageObservation: HistoryObservation?
    @State private var recentObservation: HistoryObservation?

    var body: some View {
        Page(title: greeting, subtitle: subtitle) {
            SetupBanner(app: app)

            if app.settings.collectStats {
                stats
            } else {
                Card {
                    Label("Les statistiques sont désactivées (Réglages › Général).", systemImage: "chart.bar.xaxis")
                        .foregroundStyle(.secondary)
                }
            }

            recentSection
        }
        .onAppear(perform: startObserving)
        .onDisappear {
            usageObservation = nil
            recentObservation = nil
        }
    }

    private var greeting: String {
        Calendar.current.component(.hour, from: Date()) >= 18 ? "Bonsoir" : "Bonjour"
    }

    private var subtitle: String {
        let ptt = app.settings.pushToTalkShortcut.displayString
        let free = app.settings.handsFreeShortcut.displayString
        return "Maintiens \(ptt) pour dicter dans n'importe quelle app, ou appuie sur \(free) pour une longue dictée."
    }

    private func startObserving() {
        guard let history = app.controller.history else { return }
        usageObservation = history.observeUsage { records in
            summary = UsageSummary.compute(from: records.map(\.sample))
        }
        recentObservation = history.observe(search: "", limit: 8) { recent = $0 }
    }

    // MARK: - Statistiques

    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatTile(icon: "flame.fill", value: summary.streak <= 1 ? "\(summary.streak) jour" : "\(summary.streak) jours", label: "Série en cours", tint: .orange)
                StatTile(icon: "text.word.spacing", value: summary.totalWords.formatted(), label: "Mots dictés au total")
                StatTile(icon: "speedometer", value: summary.wordsPerMinute > 0 ? "\(summary.wordsPerMinute)" : "—", label: "Mots par minute")
                StatTile(icon: "hourglass", value: Self.duration(summary.timeSaved), label: "Temps gagné", tint: .green)
            }

            HStack(alignment: .top, spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "7 derniers jours")
                            Spacer()
                            Text("\(summary.wordsToday.formatted()) aujourd'hui · \(summary.wordsThisWeek.formatted()) cette semaine")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Chart(summary.lastSevenDays) { day in
                            BarMark(
                                x: .value("Jour", day.date, unit: .day),
                                y: .value("Mots", day.words),
                                width: .ratio(0.55)
                            )
                            .foregroundStyle(Theme.ink.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine().foregroundStyle(Theme.border)
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 150)
                    }
                }
                .frame(maxWidth: .infinity)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Apps favorites")
                        if summary.topApps.isEmpty {
                            Text("Dicte dans une app pour la voir ici.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            let maxWords = max(1, summary.topApps.first?.words ?? 1)
                            ForEach(summary.topApps) { usage in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(usage.name).font(.callout).lineLimit(1)
                                        Spacer()
                                        Text(usage.words.formatted()).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    GeometryReader { proxy in
                                        Capsule().fill(Theme.ink.opacity(0.75))
                                            .frame(width: max(4, proxy.size.width * CGFloat(usage.words) / CGFloat(maxWords)))
                                    }
                                    .frame(height: 4)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(summary.totalDictations.formatted()) dictée\(summary.totalDictations > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 250)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("Temps gagné : comparé à une frappe au clavier de 40 mots par minute. Ces chiffres restent sur ton Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// « 45 s », « 12 min », « 2 h 05 ».
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        if total < 3600 { return "\(total / 60) min" }
        return String(format: "%d h %02d", total / 3600, (total % 3600) / 60)
    }

    // MARK: - Dernières dictées

    @ViewBuilder
    private var recentSection: some View {
        HStack {
            SectionLabel(text: "Récemment")
            Spacer()
            Button("Tout l'historique") { app.navigation.section = .history }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(.top, 6)

        if recent.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aucune dictée pour l'instant").font(.headline)
                    Text("Place ton curseur dans n'importe quel champ de texte, maintiens \(app.settings.pushToTalkShortcut.displayString) et parle.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Suivre le tutoriel") { app.windows.show(.tutorial) }
                        .padding(.top, 4)
                }
            }
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.leading, 90) }
                        HistoryLine(entry: entry, showsDay: true)
                    }
                }
            }
        }
    }
}

/// Bandeau d'alerte si quelque chose empêche de dicter.
private struct SetupBanner: View {
    let app: AppModel

    var body: some View {
        if !app.permissions.allGranted {
            banner(
                icon: "lock.shield",
                text: "Il manque une autorisation (micro ou Accessibilité) : Inky ne peut pas encore dicter.",
                button: "Ouvrir l'assistant"
            ) { app.windows.show(.onboarding) }
        } else if case .notInstalled = app.controller.modelStatus {
            banner(
                icon: "arrow.down.circle",
                text: "Aucun modèle de transcription n'est installé.",
                button: "Choisir un modèle"
            ) { app.navigation.section = .transcription }
        }
    }

    private func banner(icon: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            Button(button, action: action)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
