import Foundation

/// The built-in Translation prompt (#25): its instruction text, and the one flag that
/// the dictation language table cannot supply.
///
/// This was a second language table until #52. The languages you can translate into are
/// exactly the languages you can dictate in, so `DictationLanguage` is now the only list;
/// a translation tile is generated from it by `CustomPrompt.translation(to:)`.
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

    /// Flags for translation prompts stored by v0.13.x, whose target is a language you
    /// cannot dictate in.
    ///
    /// v0.13.0–v0.13.3 let you pick a translation target from a list of its own, so an
    /// upgraded install can hold a prompt for a language `DictationLanguage` has never
    /// heard of. Every other target that release offered — es, de, it, nl, pt-PT — base-matches
    /// a dictation language and is superseded by the generated tile before it is ever
    /// drawn, so Mandarin is the only one left needing a flag of its own.
    static func legacyFlag(forID id: String) -> String? {
        ["zh": "🇨🇳"][id]
    }
}
