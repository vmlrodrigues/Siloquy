import Foundation

/// A language you dictate *in* — as opposed to a language you translate *into*.
///
/// The distinction matters because they need opposite things. Translating into
/// Portuguese only changes the enhancement prompt; the microphone is still listening
/// to English. Dictating *in* Portuguese has to change the transcriber itself, and it
/// has to happen before recording starts, because by then the engine is already
/// running.
///
/// The language is therefore the unit the user chooses, and the transcription model
/// hangs off it — not the other way round. A single global "default model" is a
/// half-truth the moment there is more than one language, because it only ever
/// describes whichever language happens to be active.
struct DictationLanguage: Identifiable, Codable, Hashable {
    /// Canonical identity, always in the fullest form the app knows ("en-US", "pt-PT").
    ///
    /// Deliberately *not* the code handed to a transcriber: models disagree about the
    /// form they want, so the code is resolved per model by `languageCode(for:)`.
    let id: String
    /// Endonym: what speakers of the language call it. A Portuguese speaker looking
    /// for their language scans for "Português", not "Portuguese".
    let nativeName: String
    /// English name, for the settings list when browsing languages you don't speak.
    let englishName: String
    let flag: String
    /// Models to try, best first, when this language is enabled and has no model yet.
    ///
    /// Explicit rather than inferred, because the obvious inference is wrong: Apple
    /// matches "en-US" exactly while Parakeet only matches the base "en", so a rule
    /// preferring exact matches would quietly demote the model that measured best on
    /// English.
    let preferredModelNames: [String]

    /// English is the built-in default and cannot be removed — the app has to be able
    /// to fall back to something, and removing your only language would strand you.
    var isRemovable: Bool { id != DictationLanguage.english.id }

    var displayName: String { nativeName }

    /// The language part alone: "pt" for "pt-PT". Models that don't distinguish
    /// dialects use this form.
    var baseCode: String {
        String(id.prefix(while: { $0 != "-" }))
    }
}

extension DictationLanguage {

    /// The code `model` expects for this language, or `nil` if it cannot transcribe it.
    ///
    /// Transcribers disagree about language codes: Apple ships a per-dialect asset and
    /// wants "pt-PT", Whisper has one multilingual model and wants "pt", Parakeet is
    /// English-only and wants "en". Handing a model the wrong form does not fail
    /// loudly — `TranscriptionModelManager` silently substitutes a fallback, and the
    /// first sign is a transcript in the wrong language.
    func languageCode(for model: any TranscriptionModel) -> String? {
        let supported = TranscriptionLanguageSupport.languages(for: model)

        if supported[id] != nil { return id }
        if supported[baseCode] != nil { return baseCode }

        // A few providers spell dialects with underscores ("en_us").
        let underscored = id.lowercased().replacingOccurrences(of: "-", with: "_")
        if supported[underscored] != nil { return underscored }

        return nil
    }

    func isSupported(by model: any TranscriptionModel) -> Bool {
        languageCode(for: model) != nil
    }

    /// Another offered language shares this one's base code, so a model that only
    /// understands the base cannot tell them apart — "pt-PT" and "pt-BR" both become
    /// "pt". Where there is no sibling, dropping the region loses nothing worth saying.
    var variantSiblings: [DictationLanguage] {
        DictationLanguage.available.filter { $0.id != id && $0.baseCode == baseCode }
    }

    /// Parakeet v2 measured better on English than v3 did (v3 trades English accuracy
    /// for multilingual coverage), so English prefers the specialist model.
    static let english = DictationLanguage(
        id: "en-US",
        nativeName: "English",
        englishName: "English",
        flag: "🇬🇧",
        preferredModelNames: ["parakeet-tdt-0.6b-v2", appleNative]
    )

    /// `TranscriptionModel.name` for Apple's SpeechAnalyzer — the model's own name, not
    /// its provider ("Native Apple"), which is what `CurrentTranscriptionModel` stores.
    /// Preferred for non-English because it ships a separately tuned asset per locale
    /// and distinguishes pt-PT from pt-BR, where Parakeet v3 does not.
    static let appleNative = "apple-speech"

    /// Languages the app knows how to name and flag. A *candidate* list, not a promise:
    /// what can actually be transcribed depends on the models installed, so
    /// `DictationLanguageManager` filters it at runtime.
    static let available: [DictationLanguage] = [
        english,
        DictationLanguage(id: "pt-PT", nativeName: "Português", englishName: "Portuguese (Portugal)", flag: "🇵🇹", preferredModelNames: [appleNative]),
        DictationLanguage(id: "pt-BR", nativeName: "Português (Brasil)", englishName: "Portuguese (Brazil)", flag: "🇧🇷", preferredModelNames: [appleNative]),
        DictationLanguage(id: "es-ES", nativeName: "Español", englishName: "Spanish", flag: "🇪🇸", preferredModelNames: [appleNative]),
        DictationLanguage(id: "es-MX", nativeName: "Español (México)", englishName: "Spanish (Mexico)", flag: "🇲🇽", preferredModelNames: [appleNative]),
        DictationLanguage(id: "fr-FR", nativeName: "Français", englishName: "French", flag: "🇫🇷", preferredModelNames: [appleNative]),
        DictationLanguage(id: "de-DE", nativeName: "Deutsch", englishName: "German", flag: "🇩🇪", preferredModelNames: [appleNative]),
        DictationLanguage(id: "it-IT", nativeName: "Italiano", englishName: "Italian", flag: "🇮🇹", preferredModelNames: [appleNative]),
    ]

    /// Whether a translation target names this dictation language.
    ///
    /// The two id spaces don't line up: translation targets are coarse ("es", "de")
    /// while dictation languages are specific ("es-ES", "es-MX"). Comparing the strings
    /// directly would leave "Translate to Spanish" on offer while speaking Spanish.
    static func matches(_ translationTargetID: String, _ language: DictationLanguage) -> Bool {
        if translationTargetID == language.id { return true }
        let targetBase = String(translationTargetID.prefix(while: { $0 != "-" }))
        return targetBase == language.baseCode
    }

    static func named(_ id: String) -> DictationLanguage? {
        available.first { $0.id == id }
    }
}
