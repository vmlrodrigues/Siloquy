import AppIntents
import Combine

/// Shared signal between the Action Button / Shortcut and the running app.
/// Each press bumps `requestID`; ContentView toggles recording on every new id.
/// The intent runs in the app's process (it's declared in the app target), so
/// this singleton is the same instance the UI observes — which is what lets the
/// *same* button both start and stop.
@MainActor
final class DictationLaunch: ObservableObject {
    static let shared = DictationLaunch()
    @Published private(set) var requestID: Int = 0
    func signalToggle() { requestID += 1 }
}

struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Siloquy Dictation"
    static let description = IntentDescription("Open Siloquy and start recording — press again to stop.")

    // Must open the app: the microphone can only *start* in the foreground.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationLaunch.shared.signalToggle()
        return .result()
    }
}

/// Vends an App Shortcut so the user can bind the Action Button (Settings →
/// Action Button → Shortcut) or trigger it from Spotlight / Siri.
struct SiloquyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start dictation in \(.applicationName)",
                "Dictate with \(.applicationName)"
            ],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )
    }
}
