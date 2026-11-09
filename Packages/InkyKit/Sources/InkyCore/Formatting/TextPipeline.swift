import Foundation

/// Réglages de mise en forme (tous désactivables individuellement).
public struct FormattingOptions: Codable, Equatable, Sendable {
    /// Retirer « euh », « hum »…
    public var removeFillers = true
    /// « 14 h, non plutôt 15 h » → « 15 h »
    public var selfCorrections = true
    /// « à la ligne », « point d'interrogation »…
    public var voiceCommands = true
    /// « premièrement… deuxièmement… » → liste numérotée
    public var numberedLists = true
    /// Messageries (Messages, Slack…) : pas de point final, ton plus léger.
    public var casualStyleInMessaging = true

    public init() {}
}

/// Enchaîne toutes les étapes de transformation du texte, dans l'ordre :
///
///  1. nettoyage (hésitations, hallucinations) ;
///  2. auto-corrections orales ;
///  3. commandes vocales de mise en page ;
///  4. listes numérotées ;
///  5. dictionnaire : corrections puis snippets ;
///  6. style selon l'app (messageries).
///
/// L'ordre compte : on corrige « non plutôt » avant d'interpréter « à la
/// ligne », et les snippets passent en dernier pour que leur contenu (une
/// adresse, une signature) ne soit jamais retouché.
public struct TextPipeline: TextProcessor {
    public var options: FormattingOptions
    public var rules: [ReplacementRule]

    /// Apps de messagerie (bundle IDs) : style « décontracté ».
    public static let messagingApps: Set<String> = [
        "com.apple.MobileSMS",           // Messages
        "com.tinyspeck.slackmacgap",     // Slack
        "com.hnc.Discord",               // Discord
        "net.whatsapp.WhatsApp",         // WhatsApp
        "desktop.WhatsApp",
        "ru.keepcoder.Telegram",         // Telegram
        "org.whispersystems.signal-desktop",
        "com.facebook.archon",           // Messenger
        "com.microsoft.teams2",
    ]

    public init(options: FormattingOptions = .init(), rules: [ReplacementRule] = []) {
        self.options = options
        self.rules = rules
    }

    public func process(_ text: String, context: ProcessingContext) async throws -> String {
        format(text, context: context)
    }

    public func format(_ text: String, context: ProcessingContext = .init()) -> String {
        var result = TextCleanup(removeFillers: options.removeFillers).clean(text)
        guard !result.isEmpty else { return "" }

        if options.selfCorrections { result = SelfCorrection.apply(to: result) }
        if options.voiceCommands { result = VoiceCommands.apply(to: result) }
        if options.numberedLists { result = ListFormatter.apply(to: result) }

        let corrections = rules.filter { $0.kind == .correction }
        let snippets = rules.filter { $0.kind == .snippet }
        result = Replacements.apply(corrections, to: result)
        result = Replacements.apply(snippets, to: result)

        if options.casualStyleInMessaging,
           let bundleID = context.appBundleID,
           Self.messagingApps.contains(bundleID) {
            result = Self.casual(result)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Style messagerie : on retire le point final d'un message d'une seule
    /// phrase (personne ne finit un SMS par un point). « ? » et « ! » restent.
    static func casual(_ text: String) -> String {
        guard !text.contains("\n"), text.hasSuffix("."), !text.hasSuffix("...") else { return text }
        let body = text.dropLast()
        // Plusieurs phrases : on garde la ponctuation.
        if body.contains(where: { ".!?".contains($0) }) { return text }
        return String(body)
    }
}
