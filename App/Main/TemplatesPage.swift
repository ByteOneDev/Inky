import InkyCore
import SwiftUI

/// Prompts IA : des consignes écrites à l'avance, déclenchées à la voix, que
/// l'IA d'Apple combine avec ce qu'on dicte.
struct TemplatesPage: View {
    let app: AppModel

    @State private var availability: LanguageModelAvailability = .available

    var body: some View {
        @Bindable var settings = app.settings
        @Bindable var store = app.templates
        Page(
            title: "Prompts IA",
            subtitle: "Commence ta dictée par une phrase déclencheuse : Inky combine la consigne écrite ici avec ce que tu dis, et l'IA rédige le résultat. Tout se passe sur ton Mac."
        ) {
            statusCard

            SectionLabel(text: "Modèle d'IA").padding(.top, 6)
            LanguageModelPicker(app: app, onChange: refreshAvailability)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Exemple")
                    Text("Tu dis : « **Prompt engineering**, je veux un script Python qui renomme mes photos avec leur date. »")
                    Text("Inky insère un prompt structuré (contexte, objectif, contraintes, format attendu), prêt à coller dans ChatGPT ou Claude.")
                        .foregroundStyle(.secondary)
                    Text("Dans un mail déjà commencé : « **Complète**, dis-lui que je serai en retard et propose jeudi. » L'IA lit le début du mail et écrit la suite.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            HStack {
                SectionLabel(text: "Mes modèles")
                Spacer()
                Button("Remettre les exemples") { store.restoreExamples() }
                    .buttonStyle(.link)
                    .font(.caption)
                Button {
                    _ = store.add()
                } label: {
                    Label("Nouveau modèle", systemImage: "plus")
                }
            }
            .padding(.top, 6)

            if store.templates.isEmpty {
                Card { Text("Aucun modèle. Crée-en un ou remets les exemples.").foregroundStyle(.secondary) }
            }
            ForEach($store.templates) { $template in
                TemplateEditor(template: $template) { store.remove(template.id) }
            }

            SectionLabel(text: "Essayer sans parler").padding(.top, 6)
            TemplateTester(app: app)
        }
        .onAppear(perform: refreshAvailability)
    }

    private var statusCard: some View {
        @Bindable var settings = app.settings
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.templatesEnabled) {
                    Text("Activer les prompts IA").font(.headline)
                }
                .toggleStyle(.switch)

                HStack(alignment: .top, spacing: 8) {
                    switch availability {
                    case .available:
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("\(app.controller.languageModel.displayName) est prêt, 100 % local. Il sert aussi à la restructuration (Style).")
                    case .unavailable(let reason):
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reason)
                            Text("En attendant, les modèles « avec IA » insèrent ta dictée telle quelle ; les gabarits sans IA fonctionnent.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Ouvrir les réglages d'Apple Intelligence") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                Button("Vérifier à nouveau", action: refreshAvailability)
                            }
                        }
                    }
                }
                .font(.callout)
            }
        }
    }

    private func refreshAvailability() {
        availability = app.controller.languageModel.availability()
    }
}

/// Édition d'un modèle de prompt.
private struct TemplateEditor: View {
    @Binding var template: PromptTemplate
    let onDelete: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: template.usesAI ? "sparkles" : "doc.text")
                        .foregroundStyle(Theme.ink)
                    TextField("Nom", text: $template.name)
                        .textFieldStyle(.plain)
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $template.isEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer ce modèle")
                }

                HStack {
                    Text("Phrase déclencheuse").font(.callout).foregroundStyle(.secondary)
                    TextField("ex. prompt engineering", text: $template.trigger)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    if template.trigger.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("À remplir").font(.caption).foregroundStyle(.orange)
                    }
                }

                Text(template.usesAI ? "Consigne pour l'IA" : "Gabarit ({texte} sera remplacé par ta dictée)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $template.instructions)
                    .font(.callout)
                    .frame(minHeight: 70, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))

                HStack(spacing: 18) {
                    Toggle("Rédiger avec l'IA", isOn: $template.usesAI)
                    Toggle("Lire le texte déjà écrit dans le champ", isOn: $template.includesFieldText)
                        .disabled(!template.usesAI)
                        .help("Pour compléter un mail ou un message déjà commencé : l'IA lit le texte avant le curseur.")
                }
                .font(.callout)
            }
        }
        .opacity(template.isEnabled ? 1 : 0.6)
    }
}

/// Zone d'essai : on tape ce qu'on dirait, on voit ce qu'Inky insérerait.
private struct TemplateTester: View {
    let app: AppModel

    @State private var input = "Prompt engineering, je veux un script Python qui renomme les photos d'un dossier avec leur date de prise de vue."
    @State private var output = ""
    @State private var isRunning = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Ce que tu dirais…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                HStack {
                    Button(action: run) {
                        if isRunning { ProgressView().controlSize(.small) } else { Text("Tester") }
                    }
                    .disabled(isRunning || input.isEmpty)
                    Text("Le champ « texte déjà écrit » n'est pas lu ici.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !output.isEmpty {
                    Text(output)
                        .textSelection(.enabled)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func run() {
        guard let match = TemplateMatcher.match(input, in: app.templates.templates) else {
            output = "Aucun modèle actif ne commence par ces mots : le texte serait inséré tel quel."
            return
        }
        guard match.template.usesAI else {
            output = TemplateRenderer.fill(match.template, content: match.content)
            return
        }
        isRunning = true
        output = ""
        let request = TemplateRenderer.request(for: match.template, content: match.content, fieldText: nil)
        let model = app.controller.languageModel
        Task {
            do {
                output = TemplateRenderer.cleanResponse(try await model.generate(request))
            } catch {
                output = "⚠︎ \(error.localizedDescription)"
            }
            isRunning = false
        }
    }
}
