import AppIntents
import Foundation

extension Notification.Name {
    /// Posted (in the app's process) when the Dynamic Island "Stop" button is tapped.
    static let stopBackgroundDictation = Notification.Name("stopBackgroundDictation")
}

/// The Dynamic Island "Stop" button. `LiveActivityIntent` is guaranteed to run in
/// the app's process, so posting a notification here reaches the running
/// BackgroundDictationController (kept alive by the audio session). Stopping does
/// NOT require the foreground, so this works while you're in another app.
struct StopDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .stopBackgroundDictation, object: nil)
        return .result()
    }
}
