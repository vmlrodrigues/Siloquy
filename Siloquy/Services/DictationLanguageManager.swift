import AppKit
import Combine
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
    private let currentLanguageKey = "dictationLanguageCurrent"

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
    /// Apple locales whose assets are actually on this Mac. "Apple Speech is
    /// downloaded" is not a fact — each locale ships its own asset, so readiness is a
    /// property of the language, not of the framework.
    @Published private(set) var installedAppleLocales: Set<String> = []
    /// Languages with a download in flight, so the row can show progress instead of
    /// offering the button again.
    @Published private(set) var downloadingLanguages: Set<String> = []
    /// Mirrors `TranscriptionModelManager.usableModelNames`, which owns the expensive
    /// computation and its invalidation. Held here so views observing this manager
    /// redraw when model availability changes.
    @Published private(set) var readyModelNames: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    /// Switching a language switches the transcription model, and that has to go through
    /// the engine rather than straight to `UserDefaults`: the engine also updates its
    /// in-memory model, tears down the previous one, and normalises the language code.
    private weak var engine: (any PowerModeStateProvider)?
    /// Consulted for `usableModels` — models actually downloaded, or authorised with an
    /// API key. Offering a model that cannot run would fail only once you had spoken.
    private weak var modelManager: TranscriptionModelManager?
    /// Consulted only to refuse a switch while the microphone is open.
    private weak var recorderState: (any RecorderStateProvider)?
    private var externalChangeObserver: NSObjectProtocol?

    private init() {
        enabled = loadEnabled()
        modelNameByLanguage = UserDefaults.standard.dictionary(forKey: modelsKey) as? [String: String] ?? [:]
        // Read our own key, not SelectedLanguage: that one holds whatever code the
        // chosen transcriber wants ("nl" for Parakeet, "pt-PT" for Apple), which is not
        // a DictationLanguage.id and so could never be resolved back. Falling back to it
        // keeps upgrades from an earlier build working.
        current = DictationLanguage.named(UserDefaults.standard.string(forKey: currentLanguageKey) ?? "")
            ?? DictationLanguage.named(UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "")
            ?? .english
        Task {
            await loadAppleSupportedLocales()
            await refreshInstalledAppleLocales()
            await reconcileAppleReservations()
        }
    }

    func configure(engine: any PowerModeStateProvider, modelManager: TranscriptionModelManager) {
        self.engine = engine
        self.modelManager = modelManager
        self.recorderState = engine as? any RecorderStateProvider
        modelManager.refreshUsableModels()
        readyModelNames = modelManager.usableModelNames
        // Only now, with readiness known: resolving against an empty ready set records
        // a model that cannot run, and the choice is persisted.
        backfillMissingModels()

        // Push the restored language out before listening for anyone else's writes. At
        // launch `TranscriptionModelManager` normalises whatever `SelectedLanguage`
        // holds and posts a change; adopting that would overwrite the language we just
        // restored with the fallback it happened to pick.
        // Follow the owner rather than recomputing or listening on .AppSettingsDidChange,
        // which is posted by prompt selection and enhancement toggles — it fired the
        // Keychain walk on every ⌘1–⌘0 press during dictation, which is the cost this
        // was meant to remove.
        modelManager.$usableModelNames
            .removeDuplicates()
            .sink { [weak self] names in self?.readyModelNames = names }
            .store(in: &cancellables)

        applyCurrentLanguage()

        // `SelectedLanguage` has other writers — Power Mode applying a per-app config,
        // the menu-bar picker, and TranscriptionModelManager normalising the code after
        // a model change. Each left `current` stale, so the prompt, the recorder badge
        // and the menu-bar flag described a different language from the one being
        // transcribed. Adopting their change here fixes all three at once, rather than
        // teaching each writer about this manager.
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: .languageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.adoptExternalLanguageChange() }
        }
    }

    /// Write `current` out to the keys the transcriber reads, without going through
    /// `select()` — used at launch, where the model has already been restored and only
    /// the language code needs to agree with it.
    private func applyCurrentLanguage() {
        guard let model = model(for: current),
              let code = current.languageCode(for: model) else { return }
        UserDefaults.standard.set(code, forKey: "SelectedLanguage")
        UserDefaults.standard.set(current.id, forKey: currentLanguageKey)
        logger.notice("Restored dictation language \(self.current.id, privacy: .public) as \(code, privacy: .public)")
    }

    /// Re-derive `current` from whatever another component just wrote.
    ///
    /// No-ops when the change came from `select()`, which sets `current` before posting.
    private func adoptExternalLanguageChange() {
        guard let code = UserDefaults.standard.string(forKey: "SelectedLanguage"),
              let model = engine?.currentTranscriptionModel else { return }

        let match = enabled.first { $0.languageCode(for: model) == code && $0.id == modelNameByLanguage.first(where: { $0.value == model.name })?.key }
            ?? enabled.first { $0.languageCode(for: model) == code }
        guard let match, match != current else { return }

        current = match
        UserDefaults.standard.set(match.id, forKey: currentLanguageKey)
        logger.notice("Adopted external language change → \(match.id, privacy: .public)")
        NotificationCenter.default.post(name: .dictationLanguageDidChange, object: nil)
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
    /// Models that could transcribe this language, whether or not they are installed.
    ///
    /// Separate from `usableModels` so a language is offered when the app knows a model
    /// for it, and the row can then say which one to fetch. Filtering the offer by what
    /// is already downloaded hid Dutch entirely rather than telling you it needs
    /// Parakeet v3 — while Portuguese, whose model is present but whose locale asset is
    /// not, was offered and explained. Same situation, opposite treatment.
    func candidateModels(for language: DictationLanguage) -> [any TranscriptionModel] {
        guard let modelManager else { return [] }

        return modelManager.allAvailableModels.filter { model in
            guard language.isSupported(by: model) else { return false }
            guard modelManager.isAvailableOnCurrentOS(model) else { return false }

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
        state(of: language).selected
    }

    private func resolveModel(
        for language: DictationLanguage,
        candidates: [any TranscriptionModel],
        usable: [any TranscriptionModel]
    ) -> (any TranscriptionModel)? {
        if let chosen = modelNameByLanguage[language.id],
           let model = candidates.first(where: { $0.name == chosen }) {
            return model
        }

        // Prefer something that runs today; fall back to the best candidate so the row
        // can name what to download rather than showing no model at all.
        for preferred in language.preferredModelNames {
            if let model = usable.first(where: { $0.name == preferred }) { return model }
        }
        if let first = usable.first { return first }

        for preferred in language.preferredModelNames {
            if let model = candidates.first(where: { $0.name == preferred }) { return model }
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
        !candidateModels(for: language).isEmpty
    }

    /// Whether dictating in this language would work right now.
    ///
    /// Distinct from `isTranscribable`: German is transcribable — Apple supports it and
    /// the framework is installed — but not *ready* until its asset is downloaded.
    /// Conflating the two is what let a language be selected and then fail at the one
    /// moment an error is useless, after you had already spoken.
    func isReady(_ language: DictationLanguage) -> Bool {
        state(of: language).isReady
    }

    /// The model this language needs but which is not installed, if that is what is
    /// standing in the way.
    func missingModel(for language: DictationLanguage) -> (any TranscriptionModel)? {
        state(of: language).missing
    }

    /// Everything a language row needs, resolved once.
    ///
    /// The row used to ask four separate questions that each re-derived the same two
    /// lists; this walks the models once and answers all of them.
    struct LanguageState {
        let candidates: [any TranscriptionModel]
        let usable: [any TranscriptionModel]
        let selected: (any TranscriptionModel)?
        let isReady: Bool
        let missing: (any TranscriptionModel)?
    }

    func state(of language: DictationLanguage) -> LanguageState {
        let candidates = candidateModels(for: language)
        let usable = candidates.filter { readyModelNames.contains($0.name) }
        let selected = resolveModel(for: language, candidates: candidates, usable: usable)

        guard let selected else {
            return LanguageState(candidates: candidates, usable: usable, selected: nil, isReady: false, missing: nil)
        }

        let installed = usable.contains { $0.name == selected.name }
        let ready = installed
            && (selected.provider != .nativeApple || installedAppleLocales.contains(language.id))
        return LanguageState(
            candidates: candidates,
            usable: usable,
            selected: selected,
            isReady: ready,
            missing: installed ? nil : selected
        )
    }

    func isDownloading(_ language: DictationLanguage) -> Bool {
        downloadingLanguages.contains(language.id)
    }

    /// Keep a reservation for every enabled Apple language.
    ///
    /// A reservation is what stops macOS reclaiming an installed locale, and up to
    /// `maximumReservedLocales` can be held. Releasing them all before claiming one —
    /// which is what the single-language code did — leaves every other language
    /// unreserved and eligible for eviction, so downloading Spanish silently uninstalls
    /// Portuguese. Reserve the set, not the latest one.
    func reconcileAppleReservations(including extra: DictationLanguage? = nil) async {
        guard #available(macOS 26, *) else { return }
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        var wanted: [DictationLanguage] = enabled.filter { model(for: $0)?.provider == .nativeApple }
        if let extra, !wanted.contains(extra) { wanted.insert(extra, at: 0) }

        // The active language first, so if there are more languages than slots the one
        // being used keeps its reservation. Partitioned rather than sorted: a predicate
        // of the form `lhs == current` reports x < x as true, which is not a strict weak
        // ordering — Swift leaves the result unspecified and can trap in debug builds.
        wanted = wanted.filter { $0 == current } + wanted.filter { $0 != current }
        let keep = Array(wanted.prefix(AssetInventory.maximumReservedLocales))
        let keepIDs = Set(keep.map(\.id))

        let reserved = await AssetInventory.reservedLocales
        for locale in reserved where !keepIDs.contains(locale.identifier(.bcp47)) {
            _ = await AssetInventory.release(reservedLocale: locale)
        }

        let stillReserved = Set(await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) })
        for language in keep where !stillReserved.contains(language.id) {
            _ = try? await AssetInventory.reserve(locale: Locale(identifier: language.id))
        }

        logger.notice("Reserved Apple locales: \(keepIDs.sorted().joined(separator: ", "), privacy: .public)")
        #endif
    }

    func refreshInstalledAppleLocales() async {
        guard #available(macOS 26, *) else { return }
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        installedAppleLocales = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        #endif
    }

    /// Fetch the Apple asset for this language. Never started automatically: these are
    /// large, and a click on a language should not begin a download the user did not
    /// ask for.
    func download(_ language: DictationLanguage) async {
        guard #available(macOS 26, *) else { return }
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        guard !downloadingLanguages.contains(language.id) else { return }
        downloadingLanguages.insert(language.id)
        defer { downloadingLanguages.remove(language.id) }

        let locale = Locale(identifier: language.id)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        do {
            await reconcileAppleReservations(including: language)

            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            await refreshInstalledAppleLocales()
            logger.notice("Downloaded Apple asset for \(language.id, privacy: .public)")
        } catch {
            logger.error("Download failed for \(language.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NotificationManager.shared.showNotification(
                title: "Couldn't download \(language.nativeName): \(error.localizedDescription)",
                type: .error
            )
        }
        #endif
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
        Task { await reconcileAppleReservations() }
    }

    func disable(_ language: DictationLanguage) {
        guard language.isRemovable else { return }
        enabled.removeAll { $0 == language }
        modelNameByLanguage.removeValue(forKey: language.id)
        persistEnabled()
        UserDefaults.standard.set(modelNameByLanguage, forKey: modelsKey)
        ShortcutStore.setShortcut(nil, for: .dictationLanguage(language.id))
        // Don't leave the app set to a language you can no longer reach. Assign first:
        // select() has several guards that can refuse (mid-recording, model missing),
        // and refusing would otherwise strand `current` on a language that is no longer
        // in `enabled` — which then removes the reserved ⌘ slot and shifts every
        // translation key.
        if current == language {
            current = .english
            UserDefaults.standard.set(DictationLanguage.english.id, forKey: currentLanguageKey)
            select(.english)
        }
        NotificationCenter.default.post(name: .dictationLanguagesDidChange, object: nil)
        logger.notice("Disabled dictation language \(language.id, privacy: .public)")
        Task { await reconcileAppleReservations() }
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

        // Refuse rather than let the failure surface after a whole dictation. The row
        // says the same thing, but a shortcut can be pressed from anywhere.
        guard isReady(language) else {
            logger.notice("Refusing switch to \(language.id, privacy: .public) — asset not downloaded")
            NotificationManager.shared.showNotification(
                title: "Download \(language.nativeName) before dictating in it",
                type: .warning
            )
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
        UserDefaults.standard.set(language.id, forKey: currentLanguageKey)
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
