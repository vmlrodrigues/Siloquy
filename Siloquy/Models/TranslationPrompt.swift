import Foundation

/// The instruction behind the built-in Translation tiles (#25).
///
/// This was a second language table until #52. The languages you can translate into are
/// exactly the languages you can dictate in, so `DictationLanguage` is the only list; a
/// tile is generated from it by `CustomPrompt.translation(to:)` and never stored.
enum TranslationPrompt {
    /// The instruction, built around a language phrase from `DictationLanguage.translationPhrase`.
    ///
    /// Numbers, currency and dates are left natural to the target language — a deliberate
    /// choice, since figure-normalisation is an enhancement concern, not a translation one.
    static func text(for language: String) -> String {
        "Translate the text inside <TRANSCRIPT> into \(language). "
        + "Output only the translation — no preamble, no notes, no original text, no romanisation. "
        + "Preserve the speaker's tone, register, and meaning, and use the natural conventions "
        + "of \(language) for numbers, currency, and dates."
    }
}
