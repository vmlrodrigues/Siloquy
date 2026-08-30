import Foundation
import SwiftData
import AppKit
import os
import LLMkit

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "AIEnhancementService")

    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    /// When true, every new dictation starts with enhancement forced off and the user
    /// opts in per dictation. Persisted so it survives launches.
    @Published var resetEnhancementPerDictation: Bool {
        didSet {
            UserDefaults.standard.set(resetEnhancementPerDictation, forKey: "resetEnhancementPerDictation")
        }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            // The strip is derived from this. Without the rebuild, adding, editing or
            // deleting a prompt changed storage but not the tiles, their ⌘ keys, or the
            // text actually sent to the model.
            refreshPromptSlots()
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
            rememberSelectionForCurrentLanguage()
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var englishVariant: EnglishVariant {
        didSet {
            UserDefaults.standard.set(englishVariant.rawValue, forKey: "englishVariant")
        }
    }

    /// Block observers are keyed by token; `removeObserver(self)` in deinit does not
    /// reach them.
    private var languageObservers: [NSObjectProtocol] = []
    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: CustomPrompt? {
        guard let selectedPromptId else { return nil }
        return promptSlots.first { $0?.id == selectedPromptId } ?? nil
    }

    /// The prompts offered while dictating in the current language.
    ///
    /// Filtered, so ⌘1–⌘0 keep their meaning across a language switch: the tile in slot
    /// one is still "clean this up properly", now in the language being spoken. Muscle
    /// memory survives; content follows.
    ///
    /// Translation is filtered too, and inverts: translating into the language you are
    /// already speaking is a no-op, so that tile is hidden. Translation always means
    /// "out of the language I am speaking".
    /// Tiles in ⌘ order, with `nil` where a slot is reserved but has no tile.
    ///
    /// Every dictation language owns a permanent slot at the end of the strip, so ⌘5
    /// means the same destination wherever you are standing. The language you are
    /// currently speaking leaves its slot empty — closing the gap instead would shift
    /// every key below it, which is the failure this reservation exists to prevent, and
    /// drawing a dead tile there is the greyed-out tile it replaces.
    /// Stored, not computed. The recorder reads `activePrompt` on every audio-meter
    /// tick — about sixty times a second while you speak — and rebuilding this each
    /// time constructed a fresh translation prompt per language, each interpolating a
    /// few hundred characters, on the main actor during dictation. It changes only when
    /// the prompts or the language change, both of which are explicit events.
    @Published private(set) var promptSlots: [CustomPrompt?] = []

    private func buildPromptSlots() -> [CustomPrompt?] {
        let language = DictationLanguageManager.shared.current
        let languages = DictationLanguageManager.shared.enabled

        // Deterministic order, so ⌘1 is always the clean-up prompt. Dragging used to
        // decide this, which meant the one guarantee the language switch was built to
        // make — that ⌘1 means "clean this up properly" whatever you are speaking —
        // could be undone by a stray drag.
        let authoredAll = customPrompts.filter { prompt in
            // A stored translation prompt is superseded only where a generated tile
            // covers the same destination. One targeting a language you cannot dictate
            // in — Mandarin, say — has no generated counterpart, so it stays an
            // ordinary tile rather than being stranded with no key.
            if let target = prompt.targetLanguage {
                return !DictationLanguage.available.contains { DictationLanguage.matches(target, $0) }
            }
            return true
        }
        // Out-of-scope prompts hold their place as an empty slot rather than closing the
        // gap. Collapsing them made the authored block a different length per language,
        // which shifted every translation key below it — the exact failure the reserved
        // slots exist to prevent.
        let offered = authoredAll.map { $0.applies(to: language) ? $0 : nil }
        let authored: [CustomPrompt?] = (
            offered.filter { $0?.id == PredefinedPrompts.defaultPromptId }
            + offered.filter { $0?.id == PredefinedPrompts.assistantPromptId }
            + offered.filter { $0 == nil || ($0?.id != PredefinedPrompts.defaultPromptId && $0?.id != PredefinedPrompts.assistantPromptId) }
        )

        // With one language there is nowhere to translate to.
        guard languages.count > 1 else { return authored }

        let translations: [CustomPrompt?] = languages.map { destination in
            destination == language ? nil : CustomPrompt.translation(to: destination)
        }
        return authored + translations
    }

    /// Recompute the strip. Called when the prompts change and when the language does.
    /// Drop a selection that no longer resolves, falling back to the clean-up prompt.
    func validateSelection() {
        guard isEnhancementEnabled else { return }
        if selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId }) {
            selectedPromptId = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId })?.id
                ?? allPrompts.first?.id
        }
    }

    func refreshPromptSlots() {
        translationSlotStart = {
            let languages = DictationLanguageManager.shared.enabled
            guard languages.count > 1 else { return Int.max }
            return max(0, buildPromptSlots().count - languages.count)
        }()
        let rebuilt = buildPromptSlots()
        // Compared by value. An edited prompt keeps its id by definition, so an
        // id-only check would drop every edit — including the one this rebuild exists
        // to propagate.
        guard rebuilt != promptSlots else { return }
        promptSlots = rebuilt
    }

    /// Where the per-language translation slots begin. Anything before this index that
    /// is `nil` is a prompt scoped to another language; anything at or after it is the
    /// slot held by the language you are speaking.
    ///
    /// Stored alongside the strip rather than re-derived from the live language list:
    /// the list changes synchronously while the strip rebuilds a main-actor hop later,
    /// so a derived index disagreed with the array it indexed for at least one render —
    /// drawing an out-of-scope prompt's gap as a reserved tile, and going negative when
    /// the strip was shorter than the language count.
    @Published private(set) var translationSlotStart: Int = 0

    /// The prompts actually offered right now, in ⌘ order, with reserved gaps removed.
    var allPrompts: [CustomPrompt] {
        promptSlots.compactMap { $0 }
    }

    /// Every prompt regardless of language, for places that configure rather than
    /// dictate — Power Mode picks a prompt for an app, not for the language in use.
    var everyPrompt: [CustomPrompt] {
        customPrompts
    }

    private let selectionByLanguageKey = "selectedPromptByDictationLanguage"

    private func rememberSelectionForCurrentLanguage() {
        guard let selectedPromptId else { return }
        var map = UserDefaults.standard.dictionary(forKey: selectionByLanguageKey) as? [String: String] ?? [:]
        map[DictationLanguageManager.shared.current.id] = selectedPromptId.uuidString
        UserDefaults.standard.set(map, forKey: selectionByLanguageKey)
    }

    /// Put the selection back where this language left it.
    ///
    /// Each language keeps its own choice, so switching to Portuguese and back to
    /// English returns you to the English prompt you were using rather than resetting.
    /// Falls back to the default when the remembered prompt no longer applies.
    func restoreSelectionForCurrentLanguage() {
        let language = DictationLanguageManager.shared.current
        let map = UserDefaults.standard.dictionary(forKey: selectionByLanguageKey) as? [String: String] ?? [:]

        if let remembered = map[language.id].flatMap(UUID.init(uuidString:)),
           allPrompts.contains(where: { $0.id == remembered }) {
            if selectedPromptId != remembered { selectedPromptId = remembered }
            return
        }

        // Nothing remembered, or it belongs to another language now.
        if let current = selectedPromptId, allPrompts.contains(where: { $0.id == current }) {
            return
        }

        selectedPromptId = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId })?.id
            ?? allPrompts.first?.id
    }

    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private var baseTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        return stored > 0 ? TimeInterval(stored) : 7
    }
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        self.isEnhancementEnabled = UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")
        self.resetEnhancementPerDictation = UserDefaults.standard.bool(forKey: "resetEnhancementPerDictation")
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        let savedVariant = UserDefaults.standard.string(forKey: "englishVariant") ?? ""
        self.englishVariant = EnglishVariant(rawValue: savedVariant) ?? .american
        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }



        // Both signals matter now that the strip is stored: the active language decides
        // which slot is reserved, and the *set* of languages decides how many
        // translation tiles exist at all. Observing only the first left the strip stale
        // after adding or removing a language.
        for name in [Notification.Name.dictationLanguageDidChange, .dictationLanguagesDidChange] {
            languageObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPromptSlots()
                    self?.restoreSelectionForCurrentLanguage()
                }
            })
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        initializePredefinedPrompts()
        removeRetiredPrompts()
        removeSupersededTranslationPrompts()
        // Property observers do not fire for assignments made during init, so build the
        // strip explicitly — after the cleanups, so it is not built from prompts that
        // are about to be deleted.
        refreshPromptSlots()
        // Only now is there a strip to validate against. Doing this earlier compared the
        // saved selection to an empty list, so it was discarded on every launch.
        validateSelection()
    }

    /// Force enhancement off at the start of a new dictation when the user opted into
    /// "start each dictation with enhancement off". Called before Power Mode config and
    /// trigger-word detection, so either can still enable it for the current dictation.
    func applyPerDictationEnhancementDefault() {
        guard resetEnhancementPerDictation, isEnhancementEnabled else { return }
        isEnhancementEnabled = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        languageObservers.forEach(NotificationCenter.default.removeObserver)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage(for mode: EnhancementPrompt) async -> String {
        let selectedTextContext: String
        if AXIsProcessTrusted() {
            if let selectedText = await SelectedTextService.fetchSelectedText(), !selectedText.isEmpty {
                selectedTextContext = "\n\n<CURRENTLY_SELECTED_TEXT>\n\(selectedText)\n</CURRENTLY_SELECTED_TEXT>"
            } else {
                selectedTextContext = ""
            }
        } else {
            selectedTextContext = ""
        }

        let clipboardContext = if useClipboardContext,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
            "\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
        } else {
            ""
        }

        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\n<CURRENT_WINDOW_CONTEXT>\n\(capturedText)\n</CURRENT_WINDOW_CONTEXT>"
        } else {
            ""
        }

        let customVocabulary = customVocabularyService.getCustomVocabulary(from: modelContext)

        let allContextSections = selectedTextContext + clipboardContext + screenCaptureContext

        let customVocabularySection = if !customVocabulary.isEmpty {
            """


            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            \(customVocabulary)
            </CUSTOM_VOCABULARY>
            """
        } else {
            ""
        }

        // When dictating in another language, the English-variant appendix is not just
        // irrelevant but actively wrong — "use Australian English spelling throughout"
        // is an instruction the model will try to honour on Portuguese text. Same
        // reasoning as the translation case below. In its place, name the language, so
        // the model does not quietly drift into English.
        let dictationLanguage = DictationLanguageManager.shared.current
        let localizedPrompt = LocalizedEnhancementPrompts.systemPrompt(for: dictationLanguage)
        // Whether the localised prompt will actually be sent, not merely whether one
        // exists. The two were decided separately, so a non-English dictation with the
        // Assistant or any custom prompt got an English prompt *and* no language
        // instruction — worse than either alone.
        let willUseLocalizedPrompt = localizedPrompt != nil
            && (activePrompt == nil
                || activePrompt?.id == PredefinedPrompts.defaultPromptId
                || activePrompt?.id == PredefinedPrompts.retiredLocalModelPromptId)
        let languageSection: String
        if dictationLanguage != .english {
            // A language whose own prompt is being sent needs no hint appended: it is
            // already written in that language and states its own conventions.
            languageSection = willUseLocalizedPrompt ? "" :
                "\n\nLANGUAGE: The transcript is in \(dictationLanguage.englishName). "
                + "Reply in \(dictationLanguage.englishName) and never translate it. "
                + "Use that language's own conventions for numbers, currency, dates and times."
        } else {
            languageSection = englishVariant.promptInstruction.map {
                "\n\nLANGUAGE: \($0)"
            } ?? ""
        }

        let finalContextSection = allContextSections + customVocabularySection + languageSection

        // A Translation prompt (#25) replaces enhancement with "translate to X". The
        // custom-vocabulary and English-variant appendix would fight the target language
        // (e.g. appending "use Australian English spelling" while translating to Portuguese),
        // so translation gets only the selected-text/clipboard/window context, nothing else.
        if let activePrompt = activePrompt, activePrompt.isTranslation {
            return activePrompt.promptText + allContextSections
        }

        // For the Local (On-device) provider, the default prompt is baked in per
        // model — the selected model silently gets the prompt that measured best
        // with it (#22). A user-created custom prompt still takes precedence.
        let usesDefaultPrompt = activePrompt == nil
            || activePrompt?.id == PredefinedPrompts.defaultPromptId
            || activePrompt?.id == PredefinedPrompts.retiredLocalModelPromptId
        // The clean-up prompt swaps with the language, so ⌘1 means "clean this up
        // properly" whatever you are speaking. Replaces the whole system message rather
        // than appending to it: the English wrapper carries English input/output
        // examples, and examples steer this model harder than instructions do, so
        // leaving them in place pulls the output back towards English.
        //
        // Ahead of the per-model default below, not after it: that default is an
        // English prompt tuned for the model, and the in-language prompts were measured
        // against this very model. The language is the stronger claim.
        if let localizedPrompt, usesDefaultPrompt {
            return localizedPrompt + finalContextSection
        }

        if aiService.selectedProvider == .gemmaLocal, usesDefaultPrompt {
            let modelID = GemmaService.currentSelectedModelID
            return PredefinedPrompts.localModelPromptText(forModelID: modelID) + finalContextSection
        }

        if let activePrompt = activePrompt {
            if activePrompt.id == PredefinedPrompts.assistantPromptId {
                return activePrompt.promptText + finalContextSection
            } else {
                return activePrompt.finalPromptText + finalContextSection
            }
        } else {
            let defaultId = PredefinedPrompts.defaultPromptId
            // No force-unwrap: with the strip stored, every slot can legitimately be nil
            // (all prompts scoped to another language), and crashing here would land
            // after the user had already spoken.
            guard let defaultPrompt = allPrompts.first(where: { $0.id == defaultId }) ?? allPrompts.first else {
                return AIPrompts.customPromptTemplate.replacingOccurrences(of: "%@", with: "") + finalContextSection
            }
            return defaultPrompt.finalPromptText + finalContextSection
        }
    }

    private func makeRequest(text: String, mode: EnhancementPrompt) async throws -> String {
        guard isConfigured else {
            throw EnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        let systemMessage = await getSystemMessage(for: mode)

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(
                    text: formattedText,
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalAIError {
                    switch localError {
                    case .timeout:
                        throw EnhancementError.timeout
                    default:
                        throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                    }
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .localCLI {
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .gemmaLocal {
            do {
                let result = try await aiService.enhanceWithGemma(
                    text: formattedText,
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let gemmaError = error as? GemmaError {
                    switch gemmaError {
                    case .timeout:
                        throw EnhancementError.timeout
                    default:
                        throw EnhancementError.customError(gemmaError.errorDescription ?? "An unknown Gemma error occurred.")
                    }
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        try await waitForRateLimit()

        do {
            let result: String
            switch aiService.selectedProvider {
            case .anthropic:
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
            default:
                guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                    throw EnhancementError.customError("\(aiService.selectedProvider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                }
                let temperature = aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                let reasoningEffort = ReasoningConfig.getReasoningParameter(
                    for: aiService.selectedProvider,
                    modelName: aiService.currentModel
                )
                let extraBody = ReasoningConfig.getExtraBodyParameters(
                    for: aiService.selectedProvider,
                    modelName: aiService.currentModel
                )
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    temperature: temperature,
                    reasoningEffort: reasoningEffort,
                    extraBody: extraBody,
                    timeout: baseTimeout
                )
            }
            return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }

    private func mapLLMKitError(_ error: LLMKitError) -> EnhancementError {
        switch error {
        case .missingAPIKey:
            return .notConfigured
        case .httpError(let statusCode, let message):
            if statusCode == 429 { return .rateLimitExceeded }
            if (500...599).contains(statusCode) { return .serverError }
            return .customError("HTTP \(statusCode): \(message)")
        case .noResultReturned:
            return .enhancementFailed
        case .networkError:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .customError(error.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var retryOnTimeout: Bool {
        UserDefaults.standard.bool(forKey: "EnhancementRetryOnTimeout")
    }

    private func makeRequestWithRetry(text: String, mode: EnhancementPrompt, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(text: text, mode: mode)
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries.")
                        throw error
                    }
                case .timeout:
                    if retryOnTimeout {
                        retries += 1
                        if retries < maxRetries {
                            logger.warning("Request timed out, retrying immediately... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        } else {
                            logger.error("Request timed out after \(maxRetries, privacy: .public) retries.")
                            throw error
                        }
                    } else {
                        logger.error("Request timed out, failing immediately (retry disabled).")
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries with network error.")
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }

        throw EnhancementError.enhancementFailed
    }

    func enhance(_ text: String) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = activePrompt?.title

        do {
            let result = try await makeRequestWithRetry(text: text, mode: enhancementPrompt)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    func captureScreenContext() async {
        // Only capture when context awareness is explicitly enabled. Without this guard
        // the app hits ScreenCaptureKit on every recording (whenever Screen Recording is
        // granted) even though the feature is off by default — which is what triggers
        // macOS's periodic "bypass the window picker" consent dialog. The captured text
        // is only ever *used* when useScreenCaptureContext is true (see makeRequest), so
        // capturing while it's false was pure waste plus an unwanted system prompt.
        guard useScreenCaptureContext else { return }
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func captureClipboardContext() {
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }
    
    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        screenCaptureService.lastCapturedText = nil
    }

    func addPrompt(title: String, promptText: String, icon: PromptIcon = "doc.text.fill", description: String? = nil, triggerWords: [String] = [], useSystemInstructions: Bool = true, dictationLanguage: String? = nil) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords, useSystemInstructions: useSystemInstructions, dictationLanguage: dictationLanguage)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }



    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }

    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    /// Remove the retired "Local Model Default" prompt from existing installs (#48).
    ///
    /// `initializePredefinedPrompts` only ever appends, so dropping a prompt from the
    /// template list stops new installs seeing it but leaves it sitting in the stored
    /// list of everyone who already had it — still selectable, still occupying a
    /// ⌘-number slot. Anyone with it selected is moved to Default, which is what the
    /// on-device provider was already giving them.
    private func removeRetiredPrompts() {
        let retiredId = PredefinedPrompts.retiredLocalModelPromptId
        guard customPrompts.contains(where: { $0.id == retiredId }) else { return }

        if selectedPromptId == retiredId {
            selectedPromptId = PredefinedPrompts.defaultPromptId
        }
        customPrompts.removeAll { $0.id == retiredId }
        logger.notice("Removed the retired Local Model Default prompt (#48)")
    }

    /// Drop stored translation prompts now that they are generated from the language
    /// list.
    ///
    /// Keeping both would show the destination twice and let the two drift apart. A
    /// stored one whose target is not a dictation language is left alone — it has no
    /// generated counterpart, so removing it would silently delete a prompt the user
    /// still relies on.
    private func removeSupersededTranslationPrompts() {
        // Only the languages that will actually produce a generated tile — which means
        // enabled, and more than one enabled, since a single language has nothing to
        // translate to. Matching against every *candidate* language deleted the tile on
        // upgrade (where only English is enabled) with nothing put in its place, and it
        // could not be recreated.
        let enabled = DictationLanguageManager.shared.enabled
        guard enabled.count > 1 else { return }
        let superseded = customPrompts.filter { prompt in
            guard let target = prompt.targetLanguage else { return false }
            return enabled.contains { DictationLanguage.matches(target, $0) }
        }
        guard !superseded.isEmpty else { return }

        let supersededIds = Set(superseded.map(\.id))
        if let selected = selectedPromptId, supersededIds.contains(selected) {
            // Point at the generated tile for the same destination, so a selection is
            // carried over rather than silently reset.
            let target = superseded.first { $0.id == selected }?.targetLanguage
            selectedPromptId = target
                .flatMap { t in enabled.first { DictationLanguage.matches(t, $0) } }
                .map(\.translationPromptID)
                ?? PredefinedPrompts.defaultPromptId
        }

        customPrompts.removeAll { supersededIds.contains($0.id) }
        logger.notice("Removed \(superseded.count, privacy: .public) stored translation prompt(s) now generated from dictation languages")
    }

    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()

        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                customPrompts.append(template)
            }
        }
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        }
    }
}
