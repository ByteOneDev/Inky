import InkyMLX
import SwiftUI

/// Choix du modèle d'IA qui rédige les prompts IA et restructure le texte :
/// Apple Intelligence (intégré à macOS) ou un modèle ouvert à télécharger
/// (Mistral, Llama, Qwen, Gemma, Phi), qui tourne sur le Mac avec MLX.
struct LanguageModelPicker: View {
    let app: AppModel
    var onChange: () -> Void = {}

    var body: some View {
        let store = app.localModels
        Card(padding: 0) {
            VStack(spacing: 0) {
                row(
                    id: AppSettings.appleIntelligenceID,
                    title: "Apple Intelligence",
                    vendor: "Apple",
                    detail: "Intégré à macOS 26+, rien à télécharger. Rapide, qualité correcte.",
                    size: nil
                )
                ForEach(LocalModelCatalog.models) { info in
                    Divider().padding(.leading, 44)
                    row(
                        id: info.id,
                        title: info.displayName,
                        vendor: info.vendor,
                        detail: info.summary,
                        size: info.sizeGB,
                        recommended: info.isRecommended
                    )
                }
                if let error = store.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(12)
                }
            }
        }
        Text("Les modèles ouverts tournent sur ton Mac (GPU, via MLX d'Apple) : rien ne quitte la machine. Ils occupent 1 à 4 Go en mémoire pendant l'utilisation et sont libérés après 15 minutes d'inactivité. Le premier usage après un lancement prend quelques secondes de chargement.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(id: String, title: String, vendor: String, detail: String, size: Double?, recommended: Bool = false) -> some View {
        let store = app.localModels
        let isApple = id == AppSettings.appleIntelligenceID
        let installed = isApple || store.isInstalled(id)
        let selected = app.settings.languageModelID == id
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(installed ? Theme.ink : Color.secondary)
                .font(.title3)
                .frame(width: 20)
                .onTapGesture { if installed { select(id) } }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(selected ? .semibold : .regular)
                    Text(vendor).font(.caption).foregroundStyle(.secondary)
                    if recommended {
                        Text("Recommandé").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                Text(size.map { "\(detail) — \($0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))) Go" } ?? detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = store.downloads[id] {
                    ProgressView(value: progress).controlSize(.small)
                }
            }
            Spacer()
            if store.downloads[id] != nil {
                Button("Annuler") { store.cancelDownload(id) }
            } else if installed {
                if !selected { Button("Utiliser") { select(id) } }
                if !isApple {
                    Button(role: .destructive) {
                        if selected { select(AppSettings.appleIntelligenceID) }
                        store.delete(id)
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Supprimer du disque")
                }
            } else {
                Button("Télécharger") { store.download(id) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func select(_ id: String) {
        app.settings.languageModelID = id
        onChange()
    }
}
