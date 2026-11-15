import Foundation

/// Une dictée réduite à ce qui compte pour les statistiques : **aucun texte**,
/// seulement des nombres, une date et le nom de l'app.
public struct UsageSample: Equatable, Sendable {
    public var date: Date
    public var words: Int
    /// Durée de parole, en secondes.
    public var duration: Double
    public var appName: String?

    public init(date: Date, words: Int, duration: Double, appName: String? = nil) {
        self.date = date
        self.words = words
        self.duration = duration
        self.appName = appName
    }
}

/// Les statistiques affichées sur la page d'accueil, calculées à partir des
/// dictées. Logique pure (aucun accès disque) : testée dans `UsageSummaryTests`.
public struct UsageSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var date: Date
        public var words: Int
        public var id: Date { date }
    }

    public struct AppUsage: Equatable, Sendable, Identifiable {
        public var name: String
        public var words: Int
        public var id: String { name }
    }

    public var totalWords = 0
    public var totalDictations = 0
    public var wordsToday = 0
    public var wordsThisWeek = 0
    /// Vitesse moyenne de parole, en mots par minute (0 si aucune donnée).
    public var wordsPerMinute = 0
    /// Temps gagné par rapport à la frappe au clavier, en secondes.
    public var timeSaved: TimeInterval = 0
    /// Nombre de jours consécutifs avec au moins une dictée (aujourd'hui ou
    /// hier inclus : la série ne casse pas avant la fin de la journée).
    public var streak = 0
    /// Les 7 derniers jours, du plus ancien à aujourd'hui (jours vides inclus).
    public var lastSevenDays: [Day] = []
    /// Les apps où l'on dicte le plus, par nombre de mots.
    public var topApps: [AppUsage] = []

    public init() {}

    /// Vitesse de frappe de référence pour estimer le temps gagné. 40 mots par
    /// minute est la moyenne courante au clavier d'ordinateur.
    public static let typingWordsPerMinute = 40.0

    public static func compute(
        from samples: [UsageSample],
        now: Date = Date(),
        calendar: Calendar = .current,
        typingWordsPerMinute: Double = typingWordsPerMinute
    ) -> UsageSummary {
        var summary = UsageSummary()
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today

        var totalDuration = 0.0
        var wordsByDay: [Date: Int] = [:]
        var wordsByApp: [String: Int] = [:]

        for sample in samples {
            summary.totalWords += sample.words
            summary.totalDictations += 1
            totalDuration += sample.duration
            let day = calendar.startOfDay(for: sample.date)
            wordsByDay[day, default: 0] += sample.words
            if day == today { summary.wordsToday += sample.words }
            if sample.date >= weekStart { summary.wordsThisWeek += sample.words }
            if let app = sample.appName, !app.isEmpty { wordsByApp[app, default: 0] += sample.words }
        }

        if totalDuration > 0 {
            summary.wordsPerMinute = Int((Double(summary.totalWords) / (totalDuration / 60)).rounded())
        }
        // Temps qu'il aurait fallu pour taper ces mots, moins le temps passé à parler.
        let typingTime = Double(summary.totalWords) / typingWordsPerMinute * 60
        summary.timeSaved = max(0, typingTime - totalDuration)

        // Série : on remonte jour par jour depuis aujourd'hui (ou hier).
        var cursor = wordsByDay[today] != nil ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while wordsByDay[cursor] != nil {
            summary.streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }

        summary.lastSevenDays = (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return Day(date: day, words: wordsByDay[day] ?? 0)
        }

        summary.topApps = wordsByApp
            .map { AppUsage(name: $0.key, words: $0.value) }
            .sorted { $0.words != $1.words ? $0.words > $1.words : $0.name < $1.name }
            .prefix(5)
            .map { $0 }

        return summary
    }
}

public enum WordCounter {
    /// Nombre de mots, comme un traitement de texte : les groupes séparés par
    /// des espaces qui contiennent au moins une lettre ou un chiffre
    /// (« l'avion » compte pour un mot, « — » pour zéro).
    public static func count(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }
}
