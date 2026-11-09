import Testing
@testable import InkyInsertion

struct SmartSpacingTests {
    @Test func addsSpaceAfterWordOrSentenceEnd() {
        #expect(FocusedTextContext.applySmartSpacing(to: "comment ça va", previous: "r") == " comment ça va")
        #expect(FocusedTextContext.applySmartSpacing(to: "Ensuite", previous: ".") == " Ensuite")
    }

    @Test func noSpaceWhenNotNeeded() {
        #expect(FocusedTextContext.applySmartSpacing(to: "texte", previous: " ") == "texte")
        #expect(FocusedTextContext.applySmartSpacing(to: "texte", previous: "\n") == "texte")
        #expect(FocusedTextContext.applySmartSpacing(to: "texte", previous: "(") == "texte")
        #expect(FocusedTextContext.applySmartSpacing(to: ", et toi", previous: "i") == ", et toi")
        #expect(FocusedTextContext.applySmartSpacing(to: "texte", previous: nil) == "texte")
    }
}
