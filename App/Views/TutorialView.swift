import SwiftUI

/// Petit tutoriel interactif : chaque étape explique un geste, puis on
/// l'essaie pour de vrai dans la zone d'entraînement (Inky colle le texte dans
/// sa propre fenêtre, comme dans n'importe quelle app).
struct TutorialView: View {
    let app: AppModel

    @State private var step = 0
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool

    private struct Step {
        let icon: String
        let title: String
        let text: String
        let tryThis: String
    }

    private var steps: [Step] {
        let ptt = app.settings.pushToTalkShortcut.displayString
        let free = app.settings.handsFreeShortcut.displayString
        return [
            Step(icon: "hand.tap", title: "Push-to-talk",
                 text: "Maintiens \(ptt). La pastille affiche d'abord « Attends… » (barres grises) le temps que le micro démarre, puis un point rouge et des barres blanches qui bougent : c'est le moment de parler. Relâche pour insérer le texte.",
                 tryThis: "Clique dans la zone ci-dessous, maintiens \(ptt) et dis : « Bonjour, ceci est mon premier essai. »"),
            Step(icon: "infinity", title: "Mains libres",
                 text: "Pour une longue dictée, appuie une fois sur \(free) (sans maintenir) : la pastille affiche ✕ pour annuler et ■ pour terminer. Appuie de nouveau sur \(free) ou clique sur ■ pour insérer. Tu peux aussi démarrer en cliquant sur la petite pastille en bas de l'écran.",
                 tryThis: "Appuie sur \(free), dicte deux ou trois phrases, puis appuie de nouveau sur \(free)."),
            Step(icon: "xmark.circle", title: "Annuler",
                 text: "Pendant un enregistrement, ⎋ (Échap) annule sans rien insérer. Presser une autre touche pendant le push-to-talk annule aussi (pour que ⌃⌘Q et compagnie fonctionnent normalement).",
                 tryThis: "Lance un enregistrement, dis n'importe quoi, puis appuie sur ⎋."),
            Step(icon: "arrow.uturn.backward", title: "Auto-corrections",
                 text: "Tu t'es trompé en parlant ? Enchaîne avec « non plutôt », « je veux dire » ou « pardon » : Inky garde seulement la correction.",
                 tryThis: "Dis : « On se retrouve à 14 h, non plutôt 15 h. »"),
            Step(icon: "text.alignleft", title: "Mise en forme",
                 text: "Commandes vocales : « à la ligne », « nouveau paragraphe », « point d'interrogation », « ouvrez les guillemets »… Et « premièrement… deuxièmement… » devient une liste numérotée.",
                 tryThis: "Dis : « Pour demain, premièrement le rapport, deuxièmement les tests et troisièmement la démo. »"),
            Step(icon: "character.book.closed", title: "Dictionnaire et snippets",
                 text: "Dans Réglages › Dictionnaire : ajoute tes noms propres, corrige les mots que Whisper écorche, et crée des snippets (« mon adresse mail » → ton adresse complète).",
                 tryThis: "Ouvre les réglages, ajoute un snippet, puis dicte sa phrase déclencheuse ici."),
            Step(icon: "sparkles", title: "Prompts IA",
                 text: "Commence ta dictée par une phrase déclencheuse : l'IA d'Apple, en local, combine ta consigne écrite à l'avance avec ce que tu dis. Exemples fournis : « prompt engineering », « mail pro », « complète » (écrit la suite d'un mail déjà commencé). Tout se règle dans Inky › Prompts IA.",
                 tryThis: "Dis : « Prompt engineering, je veux une recette rapide avec des pâtes et des tomates. »"),
            Step(icon: "checkmark.seal", title: "C'est parti !",
                 text: "Inky fonctionne dans toutes les apps. Ouvre Inky depuis le menu pour voir tes statistiques et ton historique. La pastille, les sons, la mise en forme, l'IA : tout se désactive, et le menu permet de mettre Inky en pause.",
                 tryThis: "Dicte ce que tu veux pour un dernier essai."),
        ]
    }

    var body: some View {
        let current = steps[step]
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: current.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Étape \(step + 1) sur \(steps.count)").font(.caption).foregroundStyle(.secondary)
                    Text(current.title).font(.title2.bold())
                }
            }

            Text(current.text).fixedSize(horizontal: false, vertical: true)

            Label(current.tryThis, systemImage: "mic")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Zone d'entraînement").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $practice)
                    .font(.body)
                    .focused($practiceFocused)
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }

            HStack {
                Button("Effacer") { practice = "" }
                Spacer()
                if step > 0 {
                    Button("Précédent") { step -= 1 }
                }
                if step < steps.count - 1 {
                    Button("Suivant") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Terminer") {
                        app.settings.hasSeenTutorial = true
                        app.windows.close(.tutorial)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { practiceFocused = true }
    }
}
