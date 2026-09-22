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
