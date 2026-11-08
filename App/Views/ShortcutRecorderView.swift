import AppKit
import InkyHotkeys
import SwiftUI

/// Champ qui enregistre un nouveau raccourci.
///
/// Pendant l'enregistrement, on écoute les touches de NOTRE fenêtre via un
/// moniteur « local » (`addLocalMonitorForEvents`) et on met l'event tap global
/// en pause, sinon appuyer sur ⌃⌘ lancerait une dictée.
///
/// Règles :
/// - modificateurs puis une touche → combinaison (ex. ⌥Espace) ;
/// - modificateurs seuls puis tout relâché → raccourci « modificateurs seuls » ;
/// - ⎋ sans modificateur → annuler.
struct ShortcutRecorderView: View {
    @Binding var shortcut: Shortcut
    let monitor: EventTapMonitor

    @State private var isRecording = false
    @State private var pressed: ModifierSet = []
    @State private var peak: ModifierSet = []
    @State private var eventMonitor: Any?
    @State private var invalid = false

    var body: some View {
        HStack {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(label)
                    .frame(minWidth: 120)
                    .monospaced()
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if invalid {
                Text("Trop simple : 2 modificateurs minimum")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private var label: String {
        if isRecording {
            return pressed.isEmpty ? "Tape le raccourci…" : pressed.symbols
        }
        return shortcut.displayString
    }

    private func start() {
        isRecording = true
        invalid = false
        pressed = []
        peak = []
        monitor.isPaused = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handle(event)
            return nil // on avale l'événement pendant l'enregistrement
        }
    }

    private func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        isRecording = false
        monitor.isPaused = false
    }

    private func handle(_ event: NSEvent) {
        let mods = Self.modifiers(from: event.modifierFlags)
        switch event.type {
        case .flagsChanged:
            pressed = mods
            if mods.isEmpty {
                // Tout relâché : on valide le maximum de modificateurs tenus.
                if !peak.isEmpty { commit(Shortcut(modifiers: peak)) }
            } else if mods.isSuperset(of: peak) {
                peak = mods
            }
        case .keyDown:
            if event.keyCode == 0x35 && mods.isEmpty { stop(); return } // ⎋ = annuler
            var keyMods = mods
            keyMods.remove(.function)
            commit(Shortcut(modifiers: keyMods, keyCode: event.keyCode))
        default:
            break
        }
    }

    private func commit(_ candidate: Shortcut) {
        if candidate.isValid {
            shortcut = candidate
            invalid = false
            stop()
        } else {
            invalid = true
            peak = []
        }
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> ModifierSet {
        var set: ModifierSet = []
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.command) { set.insert(.command) }
        if flags.contains(.function) { set.insert(.function) }
        return set
    }
}
