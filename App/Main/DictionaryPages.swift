import InkyCore
import SwiftUI

/// Dictionnaire : mots à bien orthographier et corrections automatiques.
struct DictionaryPage: View {
    let vocabulary: VocabularyStore
    @State private var newWord = ""

    var body: some View {
        @Bindable var vocabulary = vocabulary
        Page(title: "Dictionnaire", subtitle: "Apprends à Inky tes noms propres, ton jargon, et corrige les mots que Whisper écorche.") {
            SectionLabel(text: "Mots et noms propres")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Ajouter un mot (ex. Docker, Kubernetes, Inky)", text: $newWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addWord)
                        Button("Ajouter", action: addWord)
                            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if vocabulary.words.isEmpty {
                        Text("Aucun mot pour l'instant.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        WordChips(words: vocabulary.words) { word in vocabulary.words.removeAll { $0 == word } }
                    }
                    Toggle("Donner ces mots au modèle comme amorce", isOn: $vocabulary.useWordsAsPrompt)
                    Text("L'amorce aide Whisper à bien orthographier ces mots, mais peut ralentir la transcription. Si un mot reste mal écrit, ajoute une correction ci-dessous.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SectionLabel(text: "Corrections automatiques").padding(.top, 6)
            RuleList(
                kind: .correction,
                vocabulary: vocabulary,
                triggerLabel: "Whisper écrit…",
                replacementLabel: "Remplacer par…",
                help: "Remplacement en mots entiers, sans tenir compte des majuscules. Ex. : « cube ernetes » → « Kubernetes »."
            )
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !vocabulary.words.contains(word) else { return }
        vocabulary.words.append(word)
        newWord = ""
    }
}

/// Snippets : une phrase prononcée insère un texte complet.
struct SnippetsPage: View {
    let vocabulary: VocabularyStore

    var body: some View {
        Page(title: "Snippets", subtitle: "Dis une phrase courte, Inky insère le texte complet : adresse, signature, lien, réponse type…") {
            RuleList(
                kind: .snippet,
                vocabulary: vocabulary,
                triggerLabel: "Quand je dis…",
                replacementLabel: "Insérer…",
                help: "Le snippet se déclenche quand la phrase apparaît dans la dictée, en mots entiers. Pour un texte réécrit par l'IA, utilise plutôt les Prompts IA."
            )
        }
    }
}

/// Liste éditable de règles (corrections ou snippets), dans une carte.
private struct RuleList: View {
    let kind: ReplacementRule.Kind
    let vocabulary: VocabularyStore
    let triggerLabel: String
    let replacementLabel: String
    let help: String

    var body: some View {
        @Bindable var vocabulary = vocabulary
        Card {
            VStack(alignment: .leading, spacing: 10) {
                let hasRules = vocabulary.rules.contains { $0.kind == kind }
                if !hasRules {
                    Text("Rien pour l'instant.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach($vocabulary.rules) { $rule in
                    if rule.kind == kind {
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("", isOn: $rule.isEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            TextField(triggerLabel, text: $rule.trigger)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 190)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 4)
                            TextField(replacementLabel, text: $rule.replacement, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...6)
                            Button { vocabulary.remove(ruleID: rule.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .padding(.top, 3)
                        }
                    }
                }
                HStack {
                    Button {
                        vocabulary.addRule(kind: kind)
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                    Spacer()
                }
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Mots du dictionnaire affichés en « jetons » supprimables.
private struct WordChips: View {
    let words: [String]
    let onDelete: (String) -> Void

    var body: some View {
        // Grille adaptative : autant de colonnes que la largeur le permet.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 4) {
                    Text(word).lineLimit(1)
                    Button { onDelete(word) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.selection, in: Capsule())
            }
        }
    }
}

/// Style : nettoyage, commandes vocales, adaptation à l'app.
struct StylePage: View {
    let settings: AppSettings

    var body: some View {
        @Bindable var settings = settings
        Page(title: "Style", subtitle: "Comment Inky met en forme ce que tu dis, sans IA et instantanément.") {
            SectionLabel(text: "Nettoyage")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Supprimer les hésitations (« euh », « hum »…)", isOn: $settings.formatting.removeFillers)
                    Toggle("Auto-corrections orales (« 14 h, non plutôt 15 h » → « 15 h »)", isOn: $settings.formatting.selfCorrections)
                    Text("Marqueurs reconnus : « non plutôt », « ou plutôt », « je veux dire », « pardon », « enfin non », « no wait », « I mean ».")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SectionLabel(text: "Mise en forme").padding(.top, 6)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Commandes vocales", isOn: $settings.formatting.voiceCommands)
                    Text("« à la ligne » · « nouveau paragraphe » · « point à la ligne » · « point d'interrogation » · « point d'exclamation » · « point-virgule » · « ouvrez / fermez les guillemets » · « ouvrez / fermez la parenthèse »")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Listes numérotées (« premièrement… deuxièmement… »)", isOn: $settings.formatting.numberedLists)
                }
            }

            SectionLabel(text: "Selon l'app").padding(.top, 6)
            HStack(alignment: .top, spacing: 12) {
                StyleCard(
                    icon: "bubble.left.and.bubble.right",
                    title: "Messageries",
                    detail: "Messages, Slack, Discord, WhatsApp… Pas de point final, comme quand on écrit à la main.",
                    isOn: $settings.formatting.casualStyleInMessaging
                )
                StyleCard(
                    icon: "character.cursor.ibeam",
                    title: "Espacement intelligent",
                    detail: "Ajoute une espace si tu dictes juste après un mot. Nécessite que l'app expose son texte (Accessibilité).",
                    isOn: $settings.smartSpacing
                )
            }
        }
    }
}

private struct StyleCard: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).font(.title3).foregroundStyle(Theme.ink)
                    Spacer()
                    Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
                }
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
