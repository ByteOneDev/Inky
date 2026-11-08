import Foundation

/// Marque posée sur les événements clavier qu'Inky génère lui-même (le ⌘V).
///
/// L'event tap des raccourcis voit passer *tous* les événements clavier, y
/// compris les nôtres. Grâce à cette marque (stockée dans le champ
/// `eventSourceUserData` de l'événement), il les reconnaît et les ignore.
public enum SyntheticEvents {
    /// « INKY » en ASCII, juste pour que la valeur soit reconnaissable en debug.
    public static let marker: Int64 = 0x494E_4B59
}
