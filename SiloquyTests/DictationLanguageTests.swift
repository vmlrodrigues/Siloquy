import Testing
@testable import Siloquy

@MainActor
struct DictationLanguageTests {
    private func model(_ name: String) throws -> any TranscriptionModel {
        try #require(TranscriptionModelRegistry.models.first { $0.name == name })
    }

    @Test func swedishUsesTheModelsActualLanguageCoverage() throws {
        let swedish = try #require(DictationLanguage.named("sv-SE"))
        #expect(swedish.languageCode(for: try model("parakeet-tdt-0.6b-v3")) == "sv")
        #expect(swedish.languageCode(for: try model("ggml-large-v3")) == "sv")
        #expect(swedish.languageCode(for: try model("parakeet-tdt-0.6b-v2")) == nil)
        #expect(swedish.languageCode(for: try model("apple-speech")) == nil)
        #expect(TranscriptionLanguageSupport.validLanguageOrFallback(
            "sv", for: try model("parakeet-tdt-0.6b-v3")
        ) == "sv")
    }

    @Test func missingV3RemainsSwedishRecommendationDespiteOtherDownloads() throws {
        let swedish = try #require(DictationLanguage.named("sv-SE"))
        let candidates = try [model("ggml-large-v3"), model("parakeet-tdt-0.6b-v2"), model("parakeet-tdt-0.6b-v3")]
        let ready: Set<String> = ["ggml-large-v3", "parakeet-tdt-0.6b-v2"]
        let selected = try #require(swedish.resolveModel(from: candidates, selectedName: nil, readyModelNames: ready))
        #expect(selected.name == "parakeet-tdt-0.6b-v3")
        #expect(!ready.contains(selected.name))

        let afterDownload = ready.union(["parakeet-tdt-0.6b-v3"])
        #expect(swedish.resolveModel(from: candidates, selectedName: selected.name, readyModelNames: afterDownload)?.name == selected.name)
        #expect(afterDownload.contains(selected.name))
    }

    @Test func explicitCompatibleChoiceIsPreservedEvenIfRemovedFromDisk() throws {
        let swedish = try #require(DictationLanguage.named("sv-SE"))
        let candidates = try [model("parakeet-tdt-0.6b-v3"), model("ggml-large-v3")]
        #expect(swedish.resolveModel(
            from: candidates, selectedName: "ggml-large-v3", readyModelNames: ["parakeet-tdt-0.6b-v3"]
        )?.name == "ggml-large-v3")
    }

    @Test func incompatibleSavedModelCannotBecomeTheSwedishModel() throws {
        let swedish = try #require(DictationLanguage.named("sv-SE"))
        let englishOnly = try model("parakeet-tdt-0.6b-v2")
        let v3 = try model("parakeet-tdt-0.6b-v3")
        #expect(swedish.resolveModel(
            from: [englishOnly, v3], selectedName: englishOnly.name, readyModelNames: [englishOnly.name]
        )?.name == v3.name)
        #expect(swedish.resolveModel(
            from: [englishOnly], selectedName: englishOnly.name, readyModelNames: [englishOnly.name]
        ) == nil)
    }

    @Test func englishKeepsV2WhenV3IsAlsoAvailable() throws {
        let v2 = try model("parakeet-tdt-0.6b-v2")
        let v3 = try model("parakeet-tdt-0.6b-v3")
        #expect(DictationLanguage.english.resolveModel(
            from: [v3, v2], selectedName: nil, readyModelNames: [v2.name, v3.name]
        )?.name == v2.name)
    }

    @Test func russianRecommendsV3AndAcceptsAnExplicitMultilingualWhisperModel() throws {
        let russian = try #require(DictationLanguage.named("ru-RU"))
        let v2 = try model("parakeet-tdt-0.6b-v2")
        let v3 = try model("parakeet-tdt-0.6b-v3")
        let whisper = try model("ggml-large-v3-turbo")
        let models = [v2, whisper, v3]

        #expect(russian.languageCode(for: v3) == "ru")
        #expect(russian.languageCode(for: whisper) == "ru")
        #expect(russian.languageCode(for: v2) == nil)
        #expect(TranscriptionLanguageSupport.validLanguageOrFallback("ru", for: v3) == "ru")
        #expect(russian.resolveModel(
            from: models, selectedName: nil, readyModelNames: [v2.name, whisper.name]
        )?.name == v3.name, "Recommend V3 even when it needs downloading")
        #expect(russian.resolveModel(
            from: models, selectedName: whisper.name, readyModelNames: [v3.name]
        )?.name == whisper.name, "Preserve an explicit compatible choice")
    }

    @Test func russianAndUkrainianV3AvoidScriptFiltering() throws {
        let russian = try #require(DictationLanguage.named("ru-RU"))
        let ukrainian = try #require(DictationLanguage.named("uk-UA"))
        let v3 = try model("parakeet-tdt-0.6b-v3")
        let russianCode = try #require(russian.languageCode(for: v3))
        let ukrainianCode = try #require(ukrainian.languageCode(for: v3))

        #expect(FluidAudioTranscriptionService.languageHint(from: russianCode, model: v3) == nil)
        #expect(FluidAudioTranscriptionService.languageHint(from: ukrainianCode, model: v3) == nil)
        #expect(FluidAudioTranscriptionService.languageHint(from: "pl", model: v3) == .polish)
    }

    @Test func russianUsesLocalizedCleanupAndGeneratesATranslationTile() throws {
        let russian = try #require(DictationLanguage.named("ru-RU"))
        let prompt = CustomPrompt.translation(to: russian)

        #expect(russian.nativeName == "Русский")
        #expect(russian.cleanUpPrompt == LocalizedEnhancementPrompts.russian)
        #expect(prompt.title == "To Russian")
        #expect(prompt.targetLanguage == "ru-RU")
        #expect(prompt.promptText == TranslationPrompt.text(for: "Russian"))
        #expect(prompt.id == russian.translationPromptID)
    }

    @Test(arguments: ["af-ZA", "uk-UA"])
    func newLanguagesRecommendMultilingualWhisper(_ id: String) throws {
        let language = try #require(DictationLanguage.named(id))
        let recommended = try model("ggml-large-v3-turbo-q5_0")
        let englishOnly = try model("ggml-base.en")
        let alternative = try model("ggml-large-v3")
        let parakeet = try model("parakeet-tdt-0.6b-v3")
        let models = [englishOnly, parakeet, alternative, recommended]

        #expect(language.languageCode(for: recommended) == language.baseCode)
        #expect(language.languageCode(for: englishOnly) == nil)
        #expect(language.languageCode(for: parakeet) == (id == "uk-UA" ? "uk" : nil))
        #expect(language.resolveModel(
            from: models, selectedName: nil, readyModelNames: [parakeet.name, alternative.name]
        )?.name == recommended.name)
        #expect(language.resolveModel(
            from: models, selectedName: alternative.name, readyModelNames: [recommended.name]
        )?.name == alternative.name)
    }

    @Test(arguments: ["af-ZA", "uk-UA"])
    func newLanguagesUseLocalizedCleanupAndTranslation(_ id: String) throws {
        let language = try #require(DictationLanguage.named(id))
        let cleanup = id == "af-ZA" ? LocalizedEnhancementPrompts.afrikaans : LocalizedEnhancementPrompts.ukrainian
        let target = id == "af-ZA" ? "Afrikaans" : "Ukrainian"
        let prompt = CustomPrompt.translation(to: language)

        #expect(LocalizedEnhancementPrompts.systemPrompt(for: language) == cleanup)
        #expect(prompt.title == "To \(target)")
        #expect(prompt.targetLanguage == id)
        #expect(prompt.promptText == TranslationPrompt.text(for: target))
        #expect(prompt.id == language.translationPromptID)
    }

    @Test(arguments: [("en-US", "af-ZA"), ("af-ZA", "en-US"), ("en-US", "uk-UA"), ("uk-UA", "en-US")])
    func gemmaTranslationPromptNamesBothLanguages(_ pair: (String, String)) throws {
        let source = try #require(DictationLanguage.named(pair.0))
        let target = try #require(DictationLanguage.named(pair.1))
        let prompt = try #require(TranslationPrompt.gemmaE4BText(from: source, to: target))

        #expect(prompt.contains("from \(source.englishName) into \(target.translationPhrase)"))
        #expect(prompt.contains("Docs/Plan.md"))
        #expect(prompt.contains("git status"))
    }

    @Test(arguments: [("en-US", "ru-RU"), ("ru-RU", "en-US"), ("af-ZA", "uk-UA"), ("uk-UA", "pt-PT")])
    func otherLanguagePairsKeepTheirExistingTranslationPrompt(_ pair: (String, String)) throws {
        let source = try #require(DictationLanguage.named(pair.0))
        let target = try #require(DictationLanguage.named(pair.1))

        #expect(TranslationPrompt.gemmaE4BText(from: source, to: target) == nil)
    }

    @Test func swedishHasItsOwnCleanupAndStableTranslationIdentity() throws {
        let swedish = try #require(DictationLanguage.named("sv-SE"))
        #expect(swedish.nativeName == "Svenska")
        #expect(swedish.cleanUpPrompt == LocalizedEnhancementPrompts.swedish)
        #expect(swedish.cleanUpPrompt != nil)
        #expect(swedish.translationPhrase == "Swedish (as spoken in Sweden)")
        let ids = DictationLanguage.available.map(\.translationPromptID)
        #expect(Set(ids).count == ids.count)
    }
    @Test func legacyBackfillKeepsTheCurrentCompatibleModel() throws {
        let v2 = try model("parakeet-tdt-0.6b-v2")
        let whisper = try model("ggml-large-v3")
        #expect(DictationLanguage.english.resolveModel(
            from: [v2, whisper], selectedName: nil, readyModelNames: [v2.name, whisper.name],
            context: .existingLanguage(currentModelName: whisper.name)
        )?.name == whisper.name)
        #expect(DictationLanguage.english.resolveModel(
            from: [v2, whisper], selectedName: v2.name, readyModelNames: [whisper.name],
            context: .existingLanguage(currentModelName: whisper.name)
        )?.name == v2.name, "An explicit per-language assignment still wins")
    }

    @Test func legacyBackfillUsesAnInstalledFallbackWithoutACompatibleCurrentModel() throws {
        let v2 = try model("parakeet-tdt-0.6b-v2")
        let whisper = try model("ggml-large-v3")
        for currentName in [nil, "removed-model"] as [String?] {
            #expect(DictationLanguage.english.resolveModel(
                from: [v2, whisper], selectedName: nil, readyModelNames: [whisper.name],
                context: .existingLanguage(currentModelName: currentName)
            )?.name == whisper.name)
        }
        let swedish = try #require(DictationLanguage.named("sv-SE"))
        let v3 = try model("parakeet-tdt-0.6b-v3")
        #expect(swedish.resolveModel(
            from: [v2, v3, whisper], selectedName: nil, readyModelNames: [v2.name, whisper.name],
            context: .existingLanguage(currentModelName: v2.name)
        )?.name == whisper.name, "Ignore an incompatible legacy model")
        #expect(swedish.resolveModel(
            from: [v3, whisper], selectedName: nil, readyModelNames: [whisper.name]
        )?.name == v3.name, "New Swedish still recommends V3")
    }
}
