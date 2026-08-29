import Foundation

/// A language you dictate *in* — as opposed to a language you translate *into*.
///
/// The distinction matters because they need opposite things. Translating into
/// Portuguese only changes the enhancement prompt; the microphone is still listening
/// to English. Dictating *in* Portuguese has to change the transcriber itself, and it
/// has to happen before recording starts, because by then the engine is already
/// running.
///
/// Each language therefore carries the transcription model and locale it needs, so
/// selecting one is a single decision with a single consequence rather than three
/// settings the user has to keep consistent by hand.
struct DictationLanguage: Identifiable, Codable, Hashable {
    /// The language code this language's *own transcriber* expects, and the value
    /// written to `SelectedLanguage`. Not uniformly BCP-47: Apple's models take a full
    /// locale ("pt-PT"), while Parakeet takes a bare code ("en"). Using the wrong form
    /// makes `TranscriptionModelManager` silently rewrite the value to a fallback.
    let id: String
    /// Endonym: what speakers of the language call it. A Portuguese speaker looking
    /// for their language scans for "Português", not "Portuguese".
    let nativeName: String
    /// English name, for the settings list when browsing languages you don't speak.
    let englishName: String
    let flag: String
    /// `TranscriptionModel.name` to switch to. Parakeet v2 is English-only, so every
    /// other language needs an engine that isn't it.
    let transcriptionModelName: String

    /// English is the built-in default and cannot be removed — the app has to be able
    /// to fall back to something, and removing your only language would strand you.
    var isRemovable: Bool { id != DictationLanguage.english.id }

    var displayName: String { nativeName }

    /// True when this language is transcribed by Apple, which ships a separate
    /// downloadable asset per locale. Those languages need an availability check and a
    /// download affordance; the Parakeet-backed one does not.
    var usesAppleSpeech: Bool { transcriptionModelName == DictationLanguage.appleNative }
}

extension DictationLanguage {

    /// Parakeet v2 measured better on English than v3 did (v3 trades English accuracy
    /// for multilingual coverage), so English keeps the specialist model.
    static let english = DictationLanguage(
        id: "en",
        nativeName: "English",
        englishName: "English",
        flag: "🇬🇧",
        transcriptionModelName: "parakeet-tdt-0.6b-v2"
    )

    /// Everything else routes to Apple's SpeechAnalyzer, which ships a separately tuned
    /// asset per locale rather than one model covering everything — and which
    /// distinguishes pt-PT from pt-BR, where Parakeet v3 does not.
    /// `TranscriptionModel.name` for Apple's SpeechAnalyzer — the model's own name, not
    /// its provider ("Native Apple"), which is what `CurrentTranscriptionModel` stores.
    static let appleNative = "apple-speech"

    /// Languages the app knows how to name and flag. This is a *candidate* list, not a
    /// promise: which of these can actually be transcribed depends on the locales Apple
    /// ships on the running OS, so `DictationLanguageManager` filters it at runtime.
    /// Offering one Apple cannot transcribe would fail only after the user had finished
    /// speaking, which is the worst possible moment to find out.
    static let available: [DictationLanguage] = [
        english,
        DictationLanguage(id: "pt-PT", nativeName: "Português", englishName: "Portuguese (Portugal)", flag: "🇵🇹", transcriptionModelName: appleNative),
        DictationLanguage(id: "pt-BR", nativeName: "Português (Brasil)", englishName: "Portuguese (Brazil)", flag: "🇧🇷", transcriptionModelName: appleNative),
        DictationLanguage(id: "es-ES", nativeName: "Español", englishName: "Spanish", flag: "🇪🇸", transcriptionModelName: appleNative),
        DictationLanguage(id: "es-MX", nativeName: "Español (México)", englishName: "Spanish (Mexico)", flag: "🇲🇽", transcriptionModelName: appleNative),
        DictationLanguage(id: "fr-FR", nativeName: "Français", englishName: "French", flag: "🇫🇷", transcriptionModelName: appleNative),
        DictationLanguage(id: "de-DE", nativeName: "Deutsch", englishName: "German", flag: "🇩🇪", transcriptionModelName: appleNative),
        DictationLanguage(id: "it-IT", nativeName: "Italiano", englishName: "Italian", flag: "🇮🇹", transcriptionModelName: appleNative),
    ]

    static func named(_ id: String) -> DictationLanguage? {
        available.first { $0.id == id }
    }
}
