import Foundation
import LaunchAtLogin

enum RecommendedSettings {

    struct Item {
        let icon: String
        let title: String
        let description: String
        // True when the user's current value already matches the recommendation,
        // so the sheet can show what will actually change.
        let isAlreadySet: () -> Bool
    }

    // Shown in both the onboarding screen and the Settings confirmation sheet.
    static let items: [Item] = [
        Item(icon: "menubar.rectangle",
             title: "Menu Bar Only",
             description: "Siloquy lives in your menu bar — no Dock icon.",
             isAlreadySet: { UserDefaults.standard.bool(forKey: "IsMenuBarOnly") }),
        Item(icon: "play.display",
             title: "Notch Recorder",
             description: "The recorder sits in the notch area while you speak.",
             isAlreadySet: { UserDefaults.standard.string(forKey: "RecorderType") == "notch" }),
        Item(icon: "eye",
             title: "Live Text Preview",
             description: "Watch your words appear in real time — reassuring that it's listening.",
             isAlreadySet: { UserDefaults.standard.bool(forKey: "showLiveTextPreview") }),
        Item(icon: "textformat",
             title: "Text Formatting Off",
             description: "Parakeet's text formatting is unreliable; raw output is cleaner.",
             isAlreadySet: { UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") == false }),
        Item(icon: "arrow.clockwise",
             title: "Launch at Login",
             description: "Siloquy starts automatically so it's always ready.",
             isAlreadySet: { LaunchAtLogin.isEnabled }),
        Item(icon: "speaker.wave.2",
             title: "Sound Feedback",
             description: "Audio cues confirm when recording starts and stops.",
             isAlreadySet: { UserDefaults.standard.bool(forKey: "isSoundFeedbackEnabled") }),
        Item(icon: "speaker.slash",
             title: "Mute While Recording",
             description: "Prevents your speakers from being picked up by the mic.",
             isAlreadySet: { UserDefaults.standard.bool(forKey: "isSystemMuteEnabled") }),
        Item(icon: "doc.on.clipboard",
             title: "Keep Clipboard Content",
             description: "Restores whatever was on your clipboard after Siloquy pastes.",
             isAlreadySet: { UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste") }),
    ]

    // Number of settings that don't yet match the recommendation.
    static var pendingChangeCount: Int {
        items.filter { !$0.isAlreadySet() }.count
    }

    // Apply all recommended values. Managers are passed in so @Published properties
    // update immediately (no wait for next launch). Re-applying an already-correct
    // value is a harmless no-op, so this always applies the full set.
    @MainActor
    static func apply(menuBarManager: MenuBarManager, recorderUIManager: RecorderUIManager) {
        menuBarManager.isMenuBarOnly = true
        recorderUIManager.recorderType = "notch"
        UserDefaults.standard.set(true,  forKey: "showLiveTextPreview")
        UserDefaults.standard.set(false, forKey: "IsTextFormattingEnabled")
        SoundManager.shared.isEnabled = true
        MediaController.shared.isSystemMuteEnabled = true
        UserDefaults.standard.set(true,  forKey: "restoreClipboardAfterPaste")
        LaunchAtLogin.isEnabled = true
    }
}
