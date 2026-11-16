import Testing
@testable import InkyCore

struct RestructuringTests {
    @Test func shortSentencesStayInstant() {
        #expect(!Restructuring.needsRestructuring("J'ai lancé le serveur mais ça ne marche toujours pas"))
        #expect(!Restructuring.needsRestructuring("Ensuite on verra, puis on décidera."))
    }

    @Test func enumerationsAndLongTextsAreDetected() {
        #expect(Restructuring.needsRestructuring("Pour demain il faut acheter du pain, du lait, des œufs et du beurre, puis appeler Paul."))
        #expect(Restructuring.needsRestructuring("D'abord on prépare la salle pour la réunion, ensuite on accueille les invités et enfin on lance la présentation."))
        let long = Array(repeating: "mot", count: 50).joined(separator: " ")
        #expect(Restructuring.needsRestructuring(long))
    }

    @Test func faithfulnessGuardRejectsSummaries() {
        let original = "Pour demain il faut acheter du pain du lait et des œufs ensuite appeler Paul pour le devis et le planning"
        let good = "Pour demain :\n• Acheter du pain, du lait et des œufs\n• Ensuite, appeler Paul pour le devis et le planning"
        let summary = "Courses et appel à Paul."
        #expect(Restructuring.isFaithful(good, to: original))
        #expect(!Restructuring.isFaithful(summary, to: original))
        #expect(Restructuring.accept(summary, original: original) == nil)
    }

    @Test func bulletsAreNormalized() {
        let text = "Liste :\n- un\n  - un bis\n  - un ter\n* deux\n**Note**"
        #expect(Restructuring.normalizeBullets(text) == "Liste :\n• un\n  ◦ un bis\n  ◦ un ter\n• deux\nNote")
    }

    @Test func repeatedAndLonelySubBulletsAreFixed() {
        let repeated = "Trois choses :\n• La démo\n◦ La démo\n• L'invitation\n◦ L'invitation"
        #expect(Restructuring.normalizeBullets(repeated) == "Trois choses :\n• La démo\n• L'invitation")
        let lonely = "• Réserver :\n  ◦ la salle\n• Acheter :\n  ◦ du pain\n  ◦ du lait"
        #expect(Restructuring.normalizeBullets(lonely) == "• Réserver la salle\n• Acheter :\n  ◦ du pain\n  ◦ du lait")
    }
}

struct RestructuringPlanTests {
    @Test func plansDependOnLengthAndShape() {
        #expect(Restructuring.plan(for: "Bonjour, ça va ?") == .none)
        let runOn = "Tu as mon accord pour supprimer l'ancien MCP le MCP est prêt tu peux supprimer l'ancien pack et pour l'héberger tu peux l'héberger sur le site sinon tu me donnes le pack"
        #expect(Restructuring.plan(for: runOn) == .ai)
        let long = Array(repeating: "Une phrase de test assez simple.", count: 40).joined(separator: " ")
        #expect(Restructuring.plan(for: long) == .paragraphs)
    }

    @Test func listsMayDropConnectors() {
        let original = "Pour demain il faut acheter du pain du lait et des œufs ensuite appeler Paul"
        let list = "Pour demain :\n• Acheter :\n  ◦ du pain\n  ◦ du lait\n  ◦ des œufs\n• Appeler Paul"
        #expect(Restructuring.isFaithful(list, to: original))
    }

    @Test func paragraphsSplitOnNewIdeas() {
        let text = "Je pars demain. Le train est à huit heures. Il arrive à midi. Alors pour le dîner, on verra. Je t'appelle ce soir."
        #expect(Restructuring.paragraphs(text) == "Je pars demain. Le train est à huit heures. Il arrive à midi.\n\nAlors pour le dîner, on verra. Je t'appelle ce soir.")
        #expect(Restructuring.paragraphs("Une phrase. Deux phrases.") == "Une phrase. Deux phrases.")
    }
}
