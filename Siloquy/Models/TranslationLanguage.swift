import Foundation

/// A target language offered by the built-in Translation enhancement prompt (#25).
///
/// Each language the user enables becomes an ordinary, deletable prompt tile whose
/// promptText is a self-contained translation instruction. Gemma 4 E4B handles these
/// well. The set is deliberately small for now and can grow later.
struct TranslationLanguage: Identifiable, Hashable {
    /// Stable key, also stored as `CustomPrompt.targetLanguage` (used for de-duplication).
    let id: String
    /// Tile title, e.g. "European Portuguese".
    let displayName: String
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
        .init(id: "pt-PT", displayName: "European Portuguese", promptLanguage: "European Portuguese (as spoken in Portugal)", flag: "🇵🇹"),
        .init(id: "es", displayName: "Spanish", promptLanguage: "Spanish", flag: "🇪🇸"),
        .init(id: "de", displayName: "German", promptLanguage: "German", flag: "🇩🇪"),
        .init(id: "it", displayName: "Italian", promptLanguage: "Italian", flag: "🇮🇹"),
    ]

    /// Enabled as tiles on first run.
    static let defaultSeededIDs: [String] = ["pt-PT", "es", "de", "it"]

    static func language(forID id: String) -> TranslationLanguage? {
        all.first { $0.id == id }
    }
}
