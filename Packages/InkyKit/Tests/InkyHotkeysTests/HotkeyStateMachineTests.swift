import Testing
@testable import InkyHotkeys

/// On simule des séquences de frappes et on vérifie les actions produites.
struct HotkeyStateMachineTests {
    // Raccourcis par défaut : push-to-talk ⌃⌘, mains libres ⌃⌥.
    var machine = HotkeyStateMachine()

    /// Petit utilitaire : envoie des événements, renvoie les actions non nulles.
    mutating func run(_ events: [HotkeyEvent]) -> [HotkeyAction] {
        events.compactMap { machine.handle($0).action }
    }

    func flags(_ m: ModifierSet, _ t: Double = 0) -> HotkeyEvent { .flagsChanged(modifiers: m, timestamp: t) }
    func down(_ k: UInt16, _ m: ModifierSet = [], repeat r: Bool = false) -> HotkeyEvent { .keyDown(keyCode: k, modifiers: m, isRepeat: r, timestamp: 0) }
    func up(_ k: UInt16, _ m: ModifierSet = []) -> HotkeyEvent { .keyUp(keyCode: k, modifiers: m, timestamp: 0) }

    @Test mutating func pushToTalkHoldAndRelease() {
        let actions = run([flags(.control), flags([.control, .command]), flags(.control), flags([])])
        #expect(actions == [.pushToTalkBegan, .pushToTalkEnded])
    }

    @Test mutating func pushToTalkCancelledByRealShortcut() {
        // ⌃⌘Q (verrouiller l'écran) ne doit pas déclencher de dictée.
        let actions = run([flags([.control, .command]), down(0x0C, [.control, .command]), flags([])])
        #expect(actions == [.pushToTalkBegan, .pushToTalkCancelled])
    }

    @Test mutating func pushToTalkEndsWhenExtraModifierAdded() {
        let actions = run([flags([.control, .command]), flags([.control, .command, .shift])])
        #expect(actions == [.pushToTalkBegan, .pushToTalkEnded])
    }

    @Test mutating func handsFreeTapTogglesOnRelease() {
        let actions = run([flags(.control, 0), flags([.control, .option], 0.05), flags(.option, 0.2), flags([], 0.25)])
        #expect(actions == [.handsFreeToggled])
    }

    @Test mutating func handsFreeLongHoldIsIgnored() {
        let actions = run([flags([.control, .option], 0), flags([], 3.0)])
        #expect(actions.isEmpty)
    }

    @Test mutating func handsFreeIgnoredWhenKeyPressed() {
        // ⌃⌥→ (raccourci de fenêtre, par ex.) ne doit pas basculer la dictée.
        let actions = run([flags([.control, .option]), down(0x7C, [.control, .option]), flags([])])
        #expect(actions.isEmpty)
    }

    @Test mutating func handsFreeIgnoredWhenForeignModifierAdded() {
        let actions = run([flags([.control, .option]), flags([.control, .option, .command]), flags([])])
        // ⌃⌥⌘ ne contient pas ⌃⌘ seul → pas de push-to-talk non plus.
        #expect(actions.isEmpty)
    }

    @Test mutating func escapeCancelsAndIsSwallowed() {
        machine.escapeCancels = true
        let response = machine.handle(down(0x35))
        #expect(response == HotkeyResponse(action: .cancel, swallow: true))
        #expect(machine.handle(up(0x35)).swallow)
    }

    @Test mutating func keyChordPushToTalk() {
        machine.pushToTalk = Shortcut(modifiers: .option, keyCode: 0x31) // ⌥Espace
        let r1 = machine.handle(down(0x31, .option))
        let r2 = machine.handle(down(0x31, .option, repeat: true))
        let r3 = machine.handle(up(0x31, .option))
        #expect(r1 == HotkeyResponse(action: .pushToTalkBegan, swallow: true))
        #expect(r2 == HotkeyResponse(action: nil, swallow: true))
        #expect(r3 == HotkeyResponse(action: .pushToTalkEnded, swallow: true))
    }

    @Test mutating func unrelatedTypingPassesThrough() {
        #expect(machine.handle(down(0x00)) == .passThrough)
        #expect(machine.handle(up(0x00)) == .passThrough)
    }

    @Test func shortcutValidityAndDisplay() {
        #expect(Shortcut.defaultPushToTalk.isValid)
        #expect(!Shortcut(modifiers: .command).isValid)        // ⌘ seul : trop risqué
        #expect(Shortcut(modifiers: .function).isValid)        // fn seul : accepté
        #expect(Shortcut.defaultPushToTalk.displayString == "⌃⌘")
        #expect(Shortcut(modifiers: .option, keyCode: 0x31).displayString == "⌥ Espace")
    }
}
