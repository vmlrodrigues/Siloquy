import Foundation

/// Global shortcuts that choose the language of the *next* dictation.
///
/// Deliberately separate from the mini-recorder's ⌘1–⌘0 prompt shortcuts, which are
/// only live while the recorder is on screen. By that point the microphone is open and
/// the transcriber has been chosen, so a language shortcut there would apply when you
/// pressed it early and silently do nothing when you pressed it late — the same key
/// producing different outcomes a second apart. These fire before recording instead.
///
/// One shortcut per enabled language rather than a single toggle: before recording,
/// nothing on screen states the current language, so a toggle would make you guess, and
/// guessing wrong means dictating into the wrong transcriber and only finding out after
/// you have finished speaking. Direct selection is idempotent — pressing the same key
/// twice is harmless.
@MainActor
final class DictationLanguageShortcutManager {
    private let shortcutMonitor = ShortcutMonitor()
    private var shortcutChangeObserver: NSObjectProtocol?
    private var languageChangeObserver: NSObjectProtocol?

    init() {
        refreshShortcuts()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                case .dictationLanguage = action
            else {
                return
            }
            Task { @MainActor in self?.refreshShortcuts() }
        }

        // Enabling or removing a language changes which shortcuts should be live.
        languageChangeObserver = NotificationCenter.default.addObserver(
            forName: .dictationLanguagesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshShortcuts() }
        }
    }

    deinit {
        for observer in [shortcutChangeObserver, languageChangeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        MainActor.assumeIsolated {
            shortcutMonitor.stop()
        }
    }

    private func refreshShortcuts() {
        let manager = DictationLanguageManager.shared

        // Only worth monitoring once there is somewhere to switch to. With a single
        // language the shortcut would be a no-op.
        guard manager.enabled.count > 1 else {
            shortcutMonitor.stop()
            return
        }

        let shortcuts = manager.enabled.reduce(into: [ShortcutAction: Shortcut]()) { result, language in
            let action = ShortcutAction.dictationLanguage(language.id)
            if let shortcut = ShortcutStore.shortcut(for: action) {
                result[action] = shortcut
            }
        }

        guard !shortcuts.isEmpty else {
            shortcutMonitor.stop()
            return
        }

        shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: [],
            onKeyDown: { action, _ in
                Task { @MainActor in
                    guard case .dictationLanguage(let locale) = action else { return }
                    DictationLanguageManager.shared.select(id: locale)
                }
            },
            onKeyUp: { _, _ in }
        )
    }
}
