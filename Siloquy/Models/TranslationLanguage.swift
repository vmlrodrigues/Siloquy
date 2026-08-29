import Foundation

/// A target language offered by the built-in Translation enhancement prompt (#25).
///
/// Each language the user enables becomes an ordinary, deletable prompt tile whose
/// promptText is a self-contained translation instruction. Gemma 4 E4B handles these
/// well. The set is deliberately small for now and can grow later.
struct TranslationLanguage: Identifiable, Hashable {
    /// Stable key, also stored as `CustomPrompt.targetLanguage` (used for de-duplication).
    let id: String
    /// Full name, used in pickers and descriptions where there is room.
    let displayName: String
    /// Short name for the prompt tile, which has room for about twelve characters
    /// before it truncates — "European Portuguese" became "European…", which says
    /// nothing about what the tile does.
    let shortName: String

    /// The tile's title: what pressing it does, not what the language is called.
    var tileTitle: String { "To \(shortName)" }
    /// The phrase dropped into the prompt template, e.g. "European Portuguese (as spoken in Portugal)".
    let promptLanguage: String
    /// Flag emoji shown on the tile and in the pickers.
    let flag: String

    var promptText: String {
        TranslationLanguage.promptText(for: promptLanguage)
    }

    /// Numbers, currency and dates are kept natural to the target language (a deliberate
    /// choice — figure-normalisation is an enhancement concern, not a translation one).
    static func promptText(for language: String) -> String {
        "Translate the text inside <TRANSCRIPT> into \(language). "
        + "Output only the translation — no preamble, no notes, no original text, no romanisation. "
        + "Preserve the speaker's tone, register, and meaning, and use the natural conventions "
        + "of \(language) for numbers, currency, and dates."
    }

    /// Supported languages.
    static let all: [TranslationLanguage] = [
        .init(id: "pt-PT", displayName: "European Portuguese", shortName: "Portuguese", promptLanguage: "European Portuguese (as spoken in Portugal)", flag: "🇵🇹"),
        .init(id: "es", displayName: "Spanish", shortName: "Spanish", promptLanguage: "Spanish", flag: "🇪🇸"),
        .init(id: "de", displayName: "German", shortName: "German", promptLanguage: "German", flag: "🇩🇪"),
        .init(id: "it", displayName: "Italian", shortName: "Italian", promptLanguage: "Italian", flag: "🇮🇹"),
        .init(id: "nl", displayName: "Dutch", shortName: "Dutch", promptLanguage: "Dutch", flag: "🇳🇱"),
        .init(id: "zh", displayName: "Mandarin Chinese", shortName: "Mandarin", promptLanguage: "Mandarin Chinese (Simplified)", flag: "🇨🇳"),
    ]

    /// Enabled as tiles on first run. The rest are one tap away in the Add Translation picker.
    static let defaultSeededIDs: [String] = ["pt-PT"]

    static func language(forID id: String) -> TranslationLanguage? {
        all.first { $0.id == id }
    }
}
