import Foundation

/// Numéro de version « sémantique » : MAJEUR.MINEUR.CORRECTIF (ex. 0.2.1).
///
/// Comparer des versions comme des chaînes est faux (« 0.10.0 » < « 0.9.0 » en
/// ordre alphabétique) : on compare chaque nombre séparément.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Accepte « 0.2.0 », « v0.2.0 », « 0.2 » et ignore un suffixe (« 0.2.0-beta »).
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        let parts = text.split(separator: ".").map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        major = parts[0]!
        minor = parts.count > 1 ? parts[1]! : 0
        patch = parts.count > 2 ? parts[2]! : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}
