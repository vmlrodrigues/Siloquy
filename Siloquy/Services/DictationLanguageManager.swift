import AppKit
import Foundation
import SwiftUI
import os

#if canImport(Speech)
import Speech
#endif

/// Owns the languages you dictate in, the transcription model each one uses, and the
/// switch between them.
///
/// The language is the unit of choice and the model hangs off it. `SelectedLanguage`
/// and `CurrentTranscriptionModel` still exist — the rest of the app reads them
/// everywhere — but they are now *derived*, rewritten together on every switch, rather
/// than being the place the truth lives. Keeping them as the source of truth allowed
/// the incoherent state of an English-only transcriber pointed at a Portuguese locale.
@MainActor
final class DictationLanguageManager: ObservableObject {
    static let shared = DictationLanguageManager()

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "DictationLanguage")
    private let enabledKey = "dictationLanguagesEnabled"
    private let modelsKey = "dictationLanguageModels"

    /// The languages offered for switching, in the order shown. English is always first
    /// and always present.
    @Published private(set) var enabled: [DictationLanguage] = []
    /// The language the next dictation will use.
    @Published private(set) var current: DictationLanguage = .english
    /// Which model transcribes each language, keyed by `DictationLanguage.id`.
    @Published private(set) var modelNameByLanguage: [String: String] = [:]
    /// Locales Apple can transcribe on this machine, or `nil` until the first check
    /// finishes. Empty on an OS too old for SpeechAnalyzer.
    @Published private(set) var appleSupportedLocales: Set<String>?

    /// Switching a language switches the transcription model, and that has to go through
    /// the engine rather than straight to `UserDefaults`: the engine also updates its
    /// in-memory model, tears down the previous one, and normalises the language code.
    private weak var engine: (any PowerModeStateProvider)?
    /// Consulted for `usableModels` — models actually downloaded, or authorised with an
    /// API key. Offering a model that cannot run would fail only once you had spoken.
    private weak var modelManager: TranscriptionModelManager?
    /// Consulted only to refuse a switch while the microphone is open.
    private weak var recorderState: (any RecorderStateProvider)?

    private init() {
        enabled = loadEnabled()
        modelNameByLanguage = UserDefaults.standard.dictionary(forKey: modelsKey) as? [String: String] ?? [:]
        current = DictationLanguage.named(UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "")
            ?? .english
        Task { await loadAppleSupportedLocales() }
    }

    func configure(engine: any PowerModeStateProvider, modelManager: TranscriptionModelManager) {
        self.engine = engine
        self.modelManager = modelManager
        self.recorderState = engine as? any RecorderStateProvider
        backfillMissingModels()
    }

    // MARK: - What this machine can actually transcribe

    /// Apple's locale coverage varies by OS version, so the candidate list in
    /// `DictationLanguage.available` is filtered against what is really there. Offering
    /// a language Apple cannot transcribe fails only once the user has stopped
    /// speaking — far too late to be a useful error.
    private func loadAppleSupportedLocales() async {
        guard #available(macOS 26, *) else {
            appleSupportedLocales = []
            return
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let identifiers = await Set(SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })
        appleSupportedLocales = identifiers
        logger.notice("Apple Speech can transcribe \(identifiers.count, privacy: .public) locales")
        backfillMissingModels()
        #else
        appleSupportedLocales = []
        #endif
    }

    // MARK: - Models per language

    /// Models that can transcribe `language` *and* are ready to run right now.
    ///
    /// Apple is filtered against the locales the running OS actually ships rather than
    /// the app's static table, which can be ahead of or behind the OS.
    func usableModels(for language: DictationLanguage) -> [any TranscriptionModel] {
        guard let modelManager else { return [] }

        return modelManager.usableModels.filter { model in
            guard language.isSupported(by: model) else { return false }

            // Until the OS check returns, trust the model's own table. Reporting
            // "unsupported" during that window would empty the picker at launch and,
            // worse, make the startup backfill resolve no model at all.
            if model.provider == .nativeApple, let supported = appleSupportedLocales {
                return supported.contains(language.id)
            }

            return true
        }
    }

    func model(for language: DictationLanguage) -> (any TranscriptionModel)? {
        let candidates = usableModels(for: language)

        if let chosen = modelNameByLanguage[language.id],
           let model = candidates.first(where: { $0.name == chosen }) {
            return model
        }

        // No stored choice, or the stored one is gone (deleted, or its API key removed).
        for preferred in language.preferredModelNames {
            if let model = candidates.first(where: { $0.name == preferred }) {
                return model
            }
        }

        return candidates.first
    }

    func setModel(_ model: any TranscriptionModel, for language: DictationLanguage) {
        modelNameByLanguage[language.id] = model.name
        UserDefaults.standard.set(modelNameByLanguage, forKey: modelsKey)
        logger.notice("\(language.id, privacy: .public) → \(model.name, privacy: .public)")

        // Changing the model of the language you are currently in has to take effect
        // now, not at the next switch.
        if language == current {
            select(language)
        }
    }

    /// Record the resolved model for any language that has no explicit choice, so the
    /// UI has something concrete to show and the choice survives a model being removed.
    private func backfillMissingModels() {
        for language in enabled where modelNameByLanguage[language.id] == nil {
            if let model = model(for: language) {
                modelNameByLanguage[language.id] = model.name
            }
        }
        UserDefaults.standard.set(modelNameByLanguage, forKey: modelsKey)
    }

    /// Whether this language can be transcribed here at all.
    func isTranscribable(_ language: DictationLanguage) -> Bool {
        !usableModels(for: language).isEmpty
    }

    // MARK: - The enabled list

    private func loadEnabled() -> [DictationLanguage] {
        let ids = UserDefaults.standard.stringArray(forKey: enabledKey) ?? []
        let restored = ids.compactMap(DictationLanguage.named)
        // English is the floor: it is what the app falls back to, so it can never be
        // absent no matter what is in storage.
        return restored.contains(.english) ? restored : [.english] + restored
    }

    private func persistEnabled() {
        UserDefaults.standard.set(enabled.map(\.id), forKey: enabledKey)
    }

    func enable(_ language: DictationLanguage) {
        guard !enabled.contains(language) else { return }
        enabled.append(language)
        persistEnabled()
        backfillMissingModels()
        NotificationCenter.default.post(name: .dictationLanguagesDidChange, object: nil)
        logger.notice("Enabled dictation language \(language.id, privacy: .public)")
    }

    func disable(_ language: DictationLanguage) {
        guard language.isRemovable else { return }
        enabled.removeAll { $0 == language }
        modelNameByLanguage.removeValue(forKey: language.id)
        persistEnabled()
        UserDefaults.standard.set(modelNameByLanguage, forKey: modelsKey)
        ShortcutStore.setShortcut(nil, for: .dictationLanguage(language.id))
        // Don't leave the app set to a language you can no longer reach.
        if current == language { select(.english) }
        NotificationCenter.default.post(name: .dictationLanguagesDidChange, object: nil)
        logger.notice("Disabled dictation language \(language.id, privacy: .public)")
    }

    /// Languages not yet enabled that this machine can actually transcribe.
    ///
    /// An already-enabled language is never dropped from `enabled` even if it stops
    /// being transcribable — that would silently discard the user's shortcut. The row
    /// surfaces the problem instead; only the *offer* of a new broken language is
    /// withheld.
    var addable: [DictationLanguage] {
        DictationLanguage.available.filter { !enabled.contains($0) && isTranscribable($0) }
    }

    // MARK: - Switching

    /// Point the app at a language: its model and its language code, together.
    ///
    /// Called before recording. Switching mid-recording is not offered, because the
    /// engine is already capturing by then and the choice would silently not apply.
    func select(_ language: DictationLanguage) {
        guard enabled.contains(language) else {
            logger.notice("Ignoring switch to \(language.id, privacy: .public) — not enabled")
            return
        }

        guard let engine else {
            logger.error("Cannot switch to \(language.id, privacy: .public) — no engine configured")
            return
        }

        // The transcriber is chosen when recording starts and cannot be swapped
        // underneath a live session. Letting the settings change anyway is worse than
        // refusing: the language would read as Portuguese while an English transcriber
        // kept running, so the live preview would show one language being mangled into
        // another with nothing to explain why.
        if let state = recorderState?.recordingState, state != .idle {
            logger.notice("Refusing switch to \(language.id, privacy: .public) — recorder is \(String(describing: state), privacy: .public)")
            NotificationManager.shared.showNotification(
                title: "Finish or cancel this dictation before switching to \(language.nativeName)",
                type: .warning
            )
            return
        }

        guard let model = model(for: language) else {
            logger.error("No usable model for \(language.id, privacy: .public)")
            return
        }

        guard let code = language.languageCode(for: model) else {
            logger.error("\(model.name, privacy: .public) cannot transcribe \(language.id, privacy: .public)")
            return
        }

        // Order matters. Setting the model normalises `SelectedLanguage` to whatever
        // that model accepts, so our own code has to be written afterwards or it is
        // immediately overwritten by the fallback.
        engine.setDefaultTranscriptionModel(model)
        UserDefaults.standard.set(code, forKey: "SelectedLanguage")
        current = language

        // The model that was loaded is not necessarily the one about to be used.
        Task { await engine.cleanupModelResources() }

        // `.languageDidChange` is the existing signal the rest of the app listens to;
        // the model switch above posts one carrying the fallback code, so this one has
        // to follow to leave listeners on the language actually chosen.
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .dictationLanguageDidChange, object: nil)

        // Only worth a flash when there is a choice to be ambiguous about, and only
        // when Siloquy is not in front: on screen the row already marks itself active,
        // and a HUD over the window you are looking at would just be noise.
        if enabled.count > 1, !NSApp.isActive {
            DictationLanguageHUD.shared.show(language)
        }

        logger.notice("Dictation language → \(language.id, privacy: .public) as \(code, privacy: .public) via \(model.name, privacy: .public)")
    }

    func select(id: String) {
        guard let language = DictationLanguage.named(id) else { return }
        select(language)
    }

    /// True when the app is set to dictate in something other than English — used to
    /// suppress the English-specific parts of the enhancement prompt, which would
    /// otherwise instruct the model to apply English spelling rules to another language.
    var isNonEnglish: Bool { current != .english }
}

extension Notification.Name {
    /// The active language changed — the recorder and prompt resolution follow this.
    static let dictationLanguageDidChange = Notification.Name("dictationLanguageDidChange")
    /// The set of enabled languages changed — shortcut monitoring follows this.
    static let dictationLanguagesDidChange = Notification.Name("dictationLanguagesDidChange")
}
