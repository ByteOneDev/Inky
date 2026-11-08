import Testing
@testable import InkyCore

/// Tests du nettoyage de texte (framework « Swift Testing » : @Test, #expect).
struct TextCleanupTests {
    let cleanup = TextCleanup()

    @Test func removesFrenchFillers() {
        #expect(cleanup.clean("Euh, je pense que euh c'est bon.") == "Je pense que c'est bon.")
    }

    @Test func removesBracketedTags() {
        #expect(cleanup.clean("[Musique] Bonjour à tous") == "Bonjour à tous")
        #expect(cleanup.clean("Bonjour (rires) ça va") == "Bonjour ça va")
    }

    @Test func dropsKnownHallucinations() {
        #expect(cleanup.clean(" Sous-titres réalisés par la communauté d'Amara.org") == "")
        #expect(cleanup.clean("Merci d'avoir regardé !") == "")
    }

    @Test func keepsLegitimateShortText() {
        #expect(cleanup.clean("Merci.") == "Merci.")
        #expect(cleanup.clean("  Lance le serveur  ") == "Lance le serveur")
    }

    @Test func doesNotTouchWordsContainingFillers() {
        // « humain », « heure », « umbrella » ne doivent pas être amputés.
        #expect(cleanup.clean("Un humain arrive à l'heure avec son umbrella") == "Un humain arrive à l'heure avec son umbrella")
    }

    @Test func fillersCanBeKept() {
        #expect(TextCleanup(removeFillers: false).clean("euh oui") == "euh oui")
    }
}

struct AudioClipTests {
    @Test func durationAndLevels() {
        let clip = AudioClip(samples: [Float](repeating: 0.5, count: 16_000))
        #expect(clip.duration == 1.0)
        #expect(abs(clip.rms - 0.5) < 0.0001)
        #expect(clip.peak == 0.5)
        #expect(AudioClip(samples: []).rms == 0)
    }
}
