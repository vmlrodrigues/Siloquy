import Foundation
import SwiftUI
import os

#if canImport(Speech)
import Speech
#endif

/// Owns which languages you can dictate in, and performs the switch between them.
///
/// A switch is deliberately atomic: `SelectedLanguage` and `CurrentTranscriptionModel`
/// move together. Historically they were independent settings, which allowed the
/// incoherent state of an English-only transcriber pointed at a Portuguese locale —
/// nothing warned you, and the first sign was a garbled transcript.
@MainActor
final class DictationLanguageManager: ObservableObject {
    static let shared = DictationLanguageManager()

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "DictationLanguage")
    private let enabledKey = "dictationLanguagesEnabled"

    /// The languages offered for switching, in the order shown. English is always first
    /// and always present.
    @Published private(set) var enabled: [DictationLanguage] = []
    /// The language the next dictation will use.
    @Published private(set) var current: DictationLanguage = .english
    /// Set at launch. Switching a language switches the transcription model, and that
    /// has to go through the engine rather than straight to `UserDefaults`: the engine
    /// also updates its in-memory model, tears down the previous one, and normalises
    /// the language code. Writing the defaults directly leaves the running engine on
    /// the old model until the next launch.
    private weak var engine: (any PowerModeStateProvider)?

    /// Locales Apple can transcribe on this machine, or `nil` until the first check
    /// finishes. Empty on an OS too old for SpeechAnalyzer, where English is the only
    /// language that works because it is the one not routed through Apple.
    @Published private(set) var appleSupportedLocales: Set<String>?

    private init() {
        enabled = loadEnabled()
        current = DictationLanguage.named(UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "")
            ?? .english
        Task { await loadAppleSupportedLocales() }
    }

    func configure(engine: any PowerModeStateProvider) {
        self.engine = engine
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
        #else
        appleSupportedLocales = []
        #endif
    }

    /// Whether this language can be transcribed here. Unknown while the check is still
    /// running, in which case we don't yet claim either way.
    func isTranscribable(_ language: DictationLanguage) -> Bool? {
        guard language.usesAppleSpeech else { return true }
        guard let supported = appleSupportedLocales else { return nil }
        return supported.contains(language.id)
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
        NotificationCenter.default.post(name: .dictationLanguagesDidChange, object: nil)
        logger.notice("Enabled dictation language \(language.id, privacy: .public)")
    }

    func disable(_ language: DictationLanguage) {
        guard language.isRemovable else { return }
        enabled.removeAll { $0 == language }
        persistEnabled()
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
        DictationLanguage.available.filter { language in
            guard !enabled.contains(language) else { return false }
            return isTranscribable(language) ?? false
        }
    }

    // MARK: - Switching

    /// Point the app at a language: locale and transcription model together.
    ///
    /// Called before recording. Switching mid-recording is not offered, because the
    /// engine is already capturing by then and the choice would silently not apply.
    func select(_ language: DictationLanguage) {
        guard enabled.contains(language) else {
            logger.notice("Ignoring switch to \(language.id, privacy: .public) — not enabled")
            return
        }

        guard isTranscribable(language) != false else {
            logger.error("Cannot switch to \(language.id, privacy: .public) — not transcribable on this OS")
            return
        }

        guard let engine else {
            logger.error("Cannot switch to \(language.id, privacy: .public) — no engine configured")
            return
        }

        guard let model = engine.allAvailableModels.first(where: { $0.name == language.transcriptionModelName }) else {
            logger.error("No transcription model named \(language.transcriptionModelName, privacy: .public)")
            return
        }

        // Order matters. Setting the model normalises `SelectedLanguage` to whatever
        // that model accepts, so our own locale has to be written afterwards or it is
        // immediately overwritten by the fallback.
        engine.setDefaultTranscriptionModel(model)
        UserDefaults.standard.set(language.id, forKey: "SelectedLanguage")
        current = language

        // The model that was loaded is not the one about to be used.
        Task { await engine.cleanupModelResources() }

        // `.languageDidChange` is the existing signal the rest of the app listens to;
        // the model switch above posts one carrying the fallback locale, so this one
        // has to follow to leave listeners on the language actually chosen.
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .dictationLanguageDidChange, object: nil)
        logger.notice("Dictation language → \(language.id, privacy: .public) via \(language.transcriptionModelName, privacy: .public)")
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
