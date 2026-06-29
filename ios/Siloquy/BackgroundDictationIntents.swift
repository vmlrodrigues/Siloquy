import AppIntents

/// Background dictation toggle for the Action Button.
///
/// Three conformances do the work:
/// - `AudioRecordingIntent` grants a background microphone assertion.
/// - `LiveActivityIntent` permits starting the Live Activity from the background
///   (plain `Activity.request` fails there with "Target is not foreground").
/// - `supportedModes = [.background]` (the iOS 26 replacement for the deprecated
///   `openAppWhenRun`) runs it **without launching the app**.
///
/// Under the `AudioRecordingIntent` assertion, the mic + Live Activity start straight
/// from a cold background launch — no foreground priming needed. A Live Activity must
/// stay active for the whole recording or iOS stops the mic.
struct ToggleBackgroundDictationIntent: AppIntent, AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Background Dictation"
    static let description = IntentDescription("Start or stop dictation in the background — Siloquy stays out of the way and shows progress in the Dynamic Island.")

    static let supportedModes: IntentModes = [.background]

    /// Returns the cleaned text on a stop press (nil on a start press) so a wrapping
    /// Shortcut can pipe it into "Copy to Clipboard" — the background-capable way to
    /// reach the pasteboard, which the app itself can't do from the background.
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let text = await BackgroundDictationController.shared.toggle()
        return .result(value: text)
    }
}
