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
    /// Short English name for a prompt tile, which fits about ten characters per line
    /// over two lines. "Portuguese (Portugal)" truncates to "To Portugues…", losing the
    /// word that says where the text is going; the flag carries the variant instead.
    let tileName: String
    let flag: String
    /// Models to try, best first, when this language is enabled and has no model yet.
    ///
    /// Explicit rather than inferred, because the obvious inference is wrong: Apple
    /// matches "en-US" exactly while Parakeet only matches the base "en", so a rule
    /// preferring exact matches would quietly demote the model that measured best on
    /// English.
    let preferredModelNames: [String]
    /// The clean-up prompt for this language, written in it.
    ///
    /// Declared here rather than looked up in a side table so a new language cannot be
    /// added without deciding: the field has to be filled in at the point of
    /// definition. Omitting an entry from a separate map was not a compile error, and
    /// the language silently got the English prompt — the defect the in-language
    /// prompts exist to fix. `nil` means English, which uses the app's own default
    /// prompt and its English-variant appendix.
    let cleanUpPrompt: String?
    /// How to name this language *to the model* when translating into it — more
    /// specific than the endonym, because "Portuguese" alone lets the model drift to
    /// the Brazilian norm.
    let translationPhrase: String
    /// Fixed id for this language's generated translation prompt.
    ///
    /// Derived tiles still have to be selectable and rememberable like any other
    /// prompt, and a fresh UUID each launch would lose the selection every time.
    let translationPromptID: UUID

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
        englishName: "English", tileName: "English",
        flag: "🇬🇧",
        preferredModelNames: ["parakeet-tdt-0.6b-v2", appleNative],
        cleanUpPrompt: nil,
        translationPhrase: "English",
        translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
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
        DictationLanguage(id: "pt-PT", nativeName: "Português", englishName: "Portuguese (Portugal)", tileName: "Portuguese", flag: "🇵🇹", preferredModelNames: [appleNative], cleanUpPrompt: LocalizedEnhancementPrompts.portuguesePT, translationPhrase: "European Portuguese (as spoken in Portugal)", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!),
        DictationLanguage(id: "pt-BR", nativeName: "Português (Brasil)", englishName: "Portuguese (Brazil)", tileName: "Portuguese (BR)", flag: "🇧🇷", preferredModelNames: [appleNative], cleanUpPrompt: LocalizedEnhancementPrompts.portugueseBR, translationPhrase: "Brazilian Portuguese", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E3")!),
        DictationLanguage(id: "es-ES", nativeName: "Español", englishName: "Spanish", tileName: "Spanish", flag: "🇪🇸", preferredModelNames: [appleNative], cleanUpPrompt: LocalizedEnhancementPrompts.spanishES, translationPhrase: "Spanish (as spoken in Spain)", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E4")!),
        // Apple has no Dutch model, so this one leans on Parakeet v3 — which is the
        // point of choosing a model per language: English keeps v2 and its better
        // English accuracy, and only Dutch pays v3's multilingual trade-off.
        DictationLanguage(id: "nl-NL", nativeName: "Nederlands", englishName: "Dutch", tileName: "Dutch", flag: "🇳🇱", preferredModelNames: ["parakeet-tdt-0.6b-v3"], cleanUpPrompt: LocalizedEnhancementPrompts.dutch, translationPhrase: "Dutch", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E9")!),
        DictationLanguage(id: "fr-FR", nativeName: "Français", englishName: "French", tileName: "French", flag: "🇫🇷", preferredModelNames: [appleNative], cleanUpPrompt: LocalizedEnhancementPrompts.french, translationPhrase: "French", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E6")!),
        DictationLanguage(id: "de-DE", nativeName: "Deutsch", englishName: "German", tileName: "German", flag: "🇩🇪", preferredModelNames: [appleNative], cleanUpPrompt: LocalizedEnhancementPrompts.german, translationPhrase: "German", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E7")!),
        DictationLanguage(id: "it-IT", nativeName: "Italiano", englishName: "Italian", tileName: "Italian", flag: "🇮🇹", preferredModelNames: [appleNative], cleanUpPrompt: LocalizedEnhancementPrompts.italian, translationPhrase: "Italian", translationPromptID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E8")!),
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
