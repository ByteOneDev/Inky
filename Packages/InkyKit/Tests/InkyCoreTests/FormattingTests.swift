import Testing
@testable import InkyCore

struct SelfCorrectionTests {
    @Test func replacesCorrectedWords() {
        #expect(SelfCorrection.apply(to: "Rendez-vous à 14h, non plutôt 15h.") == "Rendez-vous à 15h.")
        #expect(SelfCorrection.apply(to: "Envoie-le à Paul, je veux dire à Marie.") == "Envoie-le à Marie.")
        #expect(SelfCorrection.apply(to: "Meet me at 3, no wait, at 4.") == "Meet me at 4.")
    }

    @Test func leavesNormalSentencesAlone() {
        #expect(SelfCorrection.apply(to: "Non, je reste ici.") == "Non, je reste ici.")
        #expect(SelfCorrection.apply(to: "Je pense plutôt que oui.") == "Je pense plutôt que oui.")
    }

    @Test func onlyAffectsItsOwnSentence() {
        #expect(SelfCorrection.apply(to: "Bonjour. On se voit lundi, non plutôt mardi.") == "Bonjour. On se voit mardi.")
    }
}

struct VoiceCommandsTests {
    @Test func newLinesAndParagraphs() {
        #expect(VoiceCommands.apply(to: "Salut, à la ligne. je t'écris pour le projet.") == "Salut\nJe t'écris pour le projet.")
        #expect(VoiceCommands.apply(to: "Fin du point nouveau paragraphe suite") == "Fin du point\n\nSuite")
    }

    @Test func punctuationCommands() {
        #expect(VoiceCommands.apply(to: "Tu viens point d'interrogation") == "Tu viens?")
        #expect(VoiceCommands.apply(to: "Il a dit ouvrez les guillemets bonjour fermez les guillemets") == "Il a dit « bonjour »")
    }

    @Test func ignoresAmbiguousWords() {
        #expect(VoiceCommands.apply(to: "Le point important est trois virgule cinq.") == "Le point important est trois virgule cinq.")
    }
}

struct ListFormatterTests {
    @Test func buildsNumberedList() {
        let input = "Il faut premièrement acheter du pain, deuxièmement du lait et troisièmement des œufs."
        #expect(ListFormatter.apply(to: input) == "Il faut :\n1. Acheter du pain\n2. Du lait\n3. Des œufs")
    }

    @Test func singleOrdinalIsNotAList() {
        let input = "Premièrement, merci pour ton aide."
        #expect(ListFormatter.apply(to: input) == input)
    }
}

struct ReplacementsTests {
    @Test func correctionsAreCaseInsensitiveWholeWords() {
        let rules = [ReplacementRule(kind: .correction, trigger: "gît hub", replacement: "GitHub")]
        #expect(Replacements.apply(rules, to: "Pousse sur Gît Hub ce soir") == "Pousse sur GitHub ce soir")
        #expect(Replacements.apply([ReplacementRule(kind: .correction, trigger: "mac", replacement: "Mac")], to: "macro mac") == "macro Mac")
    }

    @Test func snippetsSwallowTrailingPunctuation() {
        let rules = [ReplacementRule(kind: .snippet, trigger: "mon adresse mail", replacement: "moi@exemple.fr")]
        #expect(Replacements.apply(rules, to: "Mon adresse mail.") == "moi@exemple.fr")
    }

    @Test func disabledRulesAreIgnored() {
        let rules = [ReplacementRule(kind: .correction, trigger: "a", replacement: "b", isEnabled: false)]
        #expect(Replacements.apply(rules, to: "a") == "a")
    }

    @Test func specialCharactersInReplacementAreLiteral() {
        let rules = [ReplacementRule(kind: .snippet, trigger: "prix", replacement: "$10 \\o/")]
        #expect(Replacements.apply(rules, to: "prix") == "$10 \\o/")
    }
}

struct TextPipelineTests {
    @Test func fullPipeline() {
        let pipeline = TextPipeline(rules: [ReplacementRule(kind: .correction, trigger: "d'aucœur", replacement: "Docker")])
        #expect(pipeline.format("Euh, relance d'aucœur à 14h, non plutôt 15h.") == "Relance Docker à 15h.")
    }

    @Test func casualStyleOnlyInMessaging() {
        let pipeline = TextPipeline()
        let slack = ProcessingContext(appBundleID: "com.tinyspeck.slackmacgap")
        #expect(pipeline.format("On se voit demain.", context: slack) == "On se voit demain")
        #expect(pipeline.format("On se voit demain.", context: .init(appBundleID: "com.apple.mail")) == "On se voit demain.")
        #expect(pipeline.format("Tu viens ?", context: slack) == "Tu viens ?")
    }

    @Test func everythingCanBeDisabled() {
        var options = FormattingOptions()
        options.removeFillers = false
        options.selfCorrections = false
        options.voiceCommands = false
        options.numberedLists = false
        let text = "euh à 14h, non plutôt 15h à la ligne"
        #expect(TextPipeline(options: options).format(text) == text)
    }
}
