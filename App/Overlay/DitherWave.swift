import SwiftUI

/// Une vague « en pointillés » façon écran rétro : la voix dessine des collines
/// lisses, faites de petits points, avec un bord tramé (dithering).
///
/// Comment c'est dessiné : l'écran est une grille de points. Pour chaque
/// colonne, on calcule la hauteur de la vague ; les points sous la vague sont
/// allumés, ceux au-dessus éteints (ou très pâles). Près du bord, on utilise
/// une **matrice de Bayer** : un motif fixe de seuils qui donne ce dégradé
/// granuleux typique des vieux écrans, sans scintillement d'une image à l'autre.
struct DitherWave: View {
    /// Niveaux récents du micro (0…1), du plus ancien au plus récent.
    let levels: [Float]
    let color: Color
    /// Distance entre deux points.
    var pitch: CGFloat = 3
    /// Diamètre d'un point.
    var dot: CGFloat = 2
    /// Afficher les points éteints (grille pâle de l'écran).
    var showsGrid = true
    /// Hauteur minimale de la vague (0…1) : une légère houle même en silence.
    var floor: Double = 0.12
    /// Vague immobile (aperçus).
    var frozen = false

    /// Matrice de Bayer 4×4, normalisée entre 0 et 1.
    private static let bayer: [[Double]] = [
        [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
    ].map { $0.map { (Double($0) + 0.5) / 16 } }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: frozen)) { context in
            let t = frozen ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                draw(in: &canvas, size: size, time: t)
            }
        }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time t: Double) {
        let smooth = Self.smoothed(levels)
        let columns = max(1, Int(size.width / pitch))
        let rows = max(1, Int(size.height / pitch))
        let xOffset = (size.width - CGFloat(columns) * pitch) / 2
        let lit = canvas.resolve(GraphicsContext.Shading.color(color))
        let dim = canvas.resolve(GraphicsContext.Shading.color(color.opacity(0.13)))

        for column in 0..<columns {
            let u = Double(column) / Double(max(columns - 1, 1))
            // Énergie de la voix à cet endroit (l'historique défile de gauche à droite).
            let energy = sqrt(Double(sample(smooth, at: u)))
            // Deux sinusoïdes lentes donnent des collines arrondies ; la voix les gonfle.
            let swell = 0.62 + 0.28 * sin(u * .pi * 1.8 + t * 1.4) + 0.1 * sin(u * .pi * 3.3 - t * 1.9)
            let height = min(0.97, floor + swell * energy * 1.25)
            let waveTop = height * Double(rows)

            for row in 0..<rows {
                let fromBottom = Double(row) + 0.5
                // > 0,5 : sous la vague. Le bord s'étale sur ~2 rangées tramées.
                let intensity = (waveTop - fromBottom) / 3 + 0.5
                let on = intensity > Self.bayer[row % 4][column % 4]
                guard on || showsGrid else { continue }
                let x = xOffset + (CGFloat(column) + 0.5) * pitch
                let y = size.height - CGFloat(fromBottom) * pitch
                let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                canvas.fill(Path(rect), with: on ? lit : dim)
            }
        }
    }

    /// Lisse l'historique (moyenne glissante, deux passes) : des collines, pas des pics.
    static func smoothed(_ levels: [Float]) -> [Float] {
        guard levels.count > 2 else { return levels }
        var values = levels
        for _ in 0..<2 {
            values = values.indices.map { i in
                let window = values[max(0, i - 2)...min(values.count - 1, i + 2)]
                return window.reduce(0, +) / Float(window.count)
            }
        }
        return values
    }

    /// Niveau interpolé (cosinus) entre deux échantillons voisins.
    private func sample(_ levels: [Float], at u: Double) -> Float {
        guard levels.count > 1 else { return levels.first ?? 0 }
        let position = u * Double(levels.count - 1)
        let index = Int(position)
        let next = min(index + 1, levels.count - 1)
        let f = Float((1 - cos((position - Double(index)) * .pi)) / 2)
        return levels[index] * (1 - f) + levels[next] * f
    }
}

/// Fond « trame » : des points dont la taille grandit vers le bas, comme une
/// image imprimée en demi-teinte.
struct HalftoneBackground: View {
    let color: Color
    var pitch: CGFloat = 5

    var body: some View {
        Canvas { canvas, size in
            canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.08)))
            let columns = Int(size.width / pitch) + 1
            let rows = Int(size.height / pitch) + 1
            for row in 0..<rows {
                let v = Double(row) / Double(max(rows - 1, 1))
                // Rien en haut, plein en bas, avec une petite ondulation.
                for column in 0..<columns {
                    let u = Double(column) / Double(max(columns - 1, 1))
                    let density = max(0, min(1, (v - 0.35 + 0.12 * sin(u * .pi * 2.5)) * 1.6))
                    guard density > 0.02 else { continue }
                    let d = pitch * 0.9 * CGFloat(density)
                    let x = CGFloat(column) * pitch, y = CGFloat(row) * pitch
                    canvas.fill(Path(CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(color.opacity(0.35 + 0.6 * density)))
                }
            }
        }
    }
}
