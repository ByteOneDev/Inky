import Foundation
import Testing
@testable import InkyCore

struct TemplateMatcherTests {
    let prompt = PromptTemplate(name: "Prompt", trigger: "prompt engineering", instructions: "…")
    let mail = PromptTemplate(name: "Mail", trigger: "mail", instructions: "…")
    let mailPro = PromptTemplate(name: "Mail pro", trigger: "mail pro", instructions: "…")
    let complete = PromptTemplate(name: "Compléter", trigger: "complète", instructions: "…", includesFieldText: true)

    @Test func matchesTriggerIgnoringCaseAccentsAndPunctuation() {
        let match = TemplateMatcher.match("Prompt Engineering, je veux un script Python.", in: [prompt])
        #expect(match?.template == prompt)
        #expect(match?.content == "Je veux un script Python.")

        let accent = TemplateMatcher.match("Complete. Dis-lui que je serai en retard.", in: [complete])
        #expect(accent?.template == complete)
        #expect(accent?.content == "Dis-lui que je serai en retard.")
    }

    @Test func triggerMustOpenTheDictation() {
        #expect(TemplateMatcher.match("Je fais du prompt engineering tous les jours.", in: [prompt]) == nil)
        // « mailbox » n'est pas « mail » : on compare des mots entiers.
        #expect(TemplateMatcher.match("Mailbox pleine.", in: [mail]) == nil)
    }

    @Test func longestTriggerWins() {
        let match = TemplateMatcher.match("Mail pro, relance le client.", in: [mail, mailPro])
        #expect(match?.template == mailPro)
        #expect(match?.content == "Relance le client.")
    }

    @Test func disabledTemplatesAreIgnoredAndContentMayBeEmpty() {
        var off = prompt
        off.isEnabled = false
        #expect(TemplateMatcher.match("Prompt engineering, test", in: [off]) == nil)
        #expect(TemplateMatcher.match("Complète.", in: [complete])?.content == "")
    }
}

struct TemplateRendererTests {
    @Test func fillReplacesPlaceholder() {
        let template = PromptTemplate(name: "T", trigger: "t", instructions: "Bonjour,\n\n{texte}\n\nCordialement", usesAI: false)
        #expect(TemplateRenderer.fill(template, content: "Merci.") == "Bonjour,\n\nMerci.\n\nCordialement")
        let noSlot = PromptTemplate(name: "T", trigger: "t", instructions: "Résume :", usesAI: false)
        #expect(TemplateRenderer.fill(noSlot, content: "abc") == "Résume :\n\nabc")
    }

    @Test func requestIncludesFieldTextOnlyWhenPresent() {
        let template = PromptTemplate(name: "C", trigger: "c", instructions: "Continue.", includesFieldText: true)
        let with = TemplateRenderer.request(for: template, content: "Propose jeudi", fieldText: "Bonjour Paul,")
        #expect(with.instructions.contains("Continue."))
        #expect(with.prompt.contains("Bonjour Paul,"))
        #expect(with.prompt.contains("Propose jeudi"))
        let without = TemplateRenderer.request(for: template, content: "Propose jeudi", fieldText: "  ")
        #expect(!without.prompt.contains("Texte déjà écrit"))
    }

    @Test func cleanResponseStripsWrappers() {
        #expect(TemplateRenderer.cleanResponse("```markdown\n# Titre\nTexte\n```") == "# Titre\nTexte")
        #expect(TemplateRenderer.cleanResponse("  \"Bonjour\"  ") == "Bonjour")
        #expect(TemplateRenderer.cleanResponse("« Salut »") == "Salut")
        #expect(TemplateRenderer.cleanResponse("Il a dit \"oui\" puis \"non\"") == "Il a dit \"oui\" puis \"non\"")
    }
}

struct UsageSummaryTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2 // lundi
        return c
    }

    /// Mercredi 11 novembre 2026, 15 h (heure de Paris).
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))! }

    func sample(daysAgo: Int, words: Int, duration: Double = 30, app: String? = nil) -> UsageSample {
        UsageSample(date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, words: words, duration: duration, appName: app)
    }

    @Test func totalsSpeedAndTimeSaved() {
        let s = UsageSummary.compute(from: [sample(daysAgo: 0, words: 100, duration: 40), sample(daysAgo: 0, words: 50, duration: 20)], now: now, calendar: calendar)
        #expect(s.totalWords == 150)
        #expect(s.totalDictations == 2)
        #expect(s.wordsToday == 150)
        #expect(s.wordsPerMinute == 150) // 150 mots en 1 min
        // 150 mots à 40 mots/min = 225 s au clavier, moins 60 s de parole.
        #expect(s.timeSaved == 165)
    }

    @Test func streakCountsConsecutiveDaysUntilTodayOrYesterday() {
        let active = [sample(daysAgo: 1, words: 1), sample(daysAgo: 2, words: 1), sample(daysAgo: 4, words: 1)]
        #expect(UsageSummary.compute(from: active, now: now, calendar: calendar).streak == 2)
        #expect(UsageSummary.compute(from: active + [sample(daysAgo: 0, words: 1)], now: now, calendar: calendar).streak == 3)
        #expect(UsageSummary.compute(from: [sample(daysAgo: 3, words: 1)], now: now, calendar: calendar).streak == 0)
    }

    @Test func weekLastSevenDaysAndTopApps() {
        let samples = [
            sample(daysAgo: 0, words: 10, app: "Slack"),
            sample(daysAgo: 2, words: 30, app: "Mail"), // lundi : même semaine
            sample(daysAgo: 3, words: 5, app: "Slack"), // dimanche : semaine précédente
            sample(daysAgo: 9, words: 7),
        ]
        let s = UsageSummary.compute(from: samples, now: now, calendar: calendar)
        #expect(s.wordsThisWeek == 40)
        #expect(s.lastSevenDays.count == 7)
        #expect(s.lastSevenDays.last?.words == 10)
        #expect(s.lastSevenDays.map(\.words).reduce(0, +) == 45)
        #expect(s.topApps.map(\.name) == ["Mail", "Slack"])
        #expect(s.topApps.first?.words == 30)
    }

    @Test func wordCounter() {
        #expect(WordCounter.count("Bonjour, l'avion décolle — à 15 h.") == 6)
        #expect(WordCounter.count("   ") == 0)
    }
}
