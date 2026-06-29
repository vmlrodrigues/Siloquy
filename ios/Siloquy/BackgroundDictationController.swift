import Foundation
import ActivityKit
import UIKit
import AudioToolbox
import os

/// Drives the *background* dictation flow used by the Action Button + Dynamic Island.
/// Records to a file via `BackgroundAudioRecorder` (the live mic engine can't start
/// backgrounded), then transcribes + enhances on stop. Heavily instrumented (see
/// DiagnosticLog) so the flow can be diagnosed from the app UI.
@MainActor
final class BackgroundDictationController: ObservableObject {
    static let shared = BackgroundDictationController()

    private let recorder = BackgroundAudioRecorder()
    private let transcription = SpeechTranscriptionService()  // on-device file transcription
    private let enhancement = EnhancementService()
    private var activity: Activity<DictationActivityAttributes>?
    @Published private(set) var isRecording = false

    /// Unique per app-process launch. If two consecutive presses show different
    /// IDs, the background process was killed between them.
    private let proc = String(UUID().uuidString.prefix(4))

    private let log = Logger(subsystem: "com.victorrodrigues.siloquy.ios", category: "bg-dictation")
    private var diag: DiagnosticLog { DiagnosticLog.shared }

    private init() {
        // The Dynamic Island "Stop" button (a LiveActivityIntent) posts this in our
        // process; we react here. Stopping needs no foreground, so this works from
        // any app.
        NotificationCenter.default.addObserver(
            forName: .stopBackgroundDictation, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stopIfRecording(trigger: "DynamicIsland") }
        }
    }

    /// Warm the mic pipeline while the app is in the foreground so the first background
    /// record from the Action Button fires reliably. Call whenever the app becomes active.
    func warmUpSession() {
        guard !isRecording else { return }
        Task {
            do {
                try await recorder.prime()
                diag.log("  prime: mic pipeline warmed ✅ (proc \(proc))")
            } catch {
                diag.log("  prime: FAILED ❌ \(error.localizedDescription)")
            }
        }
    }

    /// Returns the cleaned text on a stop (for a wrapping Shortcut's "Copy to
    /// Clipboard"), or nil on a start.
    func toggle() async -> String? {
        let appState = Self.stateName(UIApplication.shared.applicationState)
        let liveActivities = !Activity<DictationActivityAttributes>.activities.isEmpty
        diag.log("▶︎ TOGGLE  proc=\(proc)  isRecording=\(isRecording)  liveActivities=\(liveActivities)  appState=\(appState)")
        if isRecording { return await stop(trigger: "ActionButton") }
        await start()
        return nil
    }

    @discardableResult
    func stopIfRecording(trigger: String) async -> String? {
        guard isRecording else {
            diag.log("  stop(\(trigger)): ignored — not recording")
            return nil
        }
        return await stop(trigger: trigger)
    }

    private func start() async {
        guard !isRecording else { return }

        // Clear any orphaned Live Activities from a previous failed attempt so we
        // don't leave a ghost "couldn't start" bar on screen.
        for old in Activity<DictationActivityAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil

        diag.log("  start: requesting Live Activity…")
        var liveActivityOK = false
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(
                    attributes: DictationActivityAttributes(),
                    content: ActivityContent(state: .init(status: "Recording…", startedAt: Date()), staleDate: nil)
                )
                liveActivityOK = true
                diag.log("  start: Live Activity OK")
            } catch {
                diag.log("  start: Live Activity FAILED ❌ \(error.localizedDescription)")
            }
        } else {
            diag.log("  start: Live Activities DISABLED in Settings ⚠️")
        }

        // AudioRecordingIntent fatal-errors if it leaves an active session without a
        // Live Activity — so bail (and relinquish the session) rather than crash.
        guard liveActivityOK else {
            diag.log("  start: aborting — no Live Activity; relinquishing session")
            recorder.releaseSession()
            return
        }

        diag.log("  start: AVAudioRecorder.record()…")
        do {
            try await recorder.start()
            isRecording = true
            diag.log("  start: recording STARTED ✅ (proc \(proc))")
        } catch {
            diag.log("  start: recording FAILED ❌ \(error.localizedDescription)")
            recorder.releaseSession()
            await endActivity(status: "Couldn't start")
        }
    }

    private func stop(trigger: String) async -> String? {
        guard isRecording else { return nil }
        diag.log("  stop(\(trigger)): finalizing recording…")
        let (url, bytes) = recorder.stop()
        // Release the session immediately: a toggle/stop runs as an AudioRecordingIntent
        // and must not end with an active session and no Live Activity. File
        // transcription below reads the file directly and needs no session.
        recorder.releaseSession()
        isRecording = false
        diag.log("  stop: captured file \(bytes) bytes")

        guard let url, bytes > 4096 else {
            await endActivity(status: "Nothing captured")
            return nil
        }

        await updateActivity(status: "Transcribing…")
        let raw: String
        do {
            raw = try await transcription.transcribeFile(url)
        } catch {
            diag.log("  stop: transcription FAILED ❌ \(error.localizedDescription)")
            await endActivity(status: "Couldn't transcribe")
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        diag.log("  stop: transcribed \(trimmed.count) chars")
        guard !trimmed.isEmpty else {
            await endActivity(status: "No speech detected")
            return nil
        }

        await updateActivity(status: "Cleaning up…")
        let output = await enhancement.enhance(trimmed)
        diag.log("  stop: enhanced \(output.count) chars")

        // Best-effort in-app write (works when foreground); the wrapping Shortcut's
        // "Copy to Clipboard" action is what lands it in the background. We also
        // return the text so the Shortcut can copy it.
        UIPasteboard.general.string = output
        // A system vibration (unlike UIFeedbackGenerator) still fires when we're
        // backgrounded — the "done" buzz.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        diag.log("  stop: returning \(output.count) chars to the Shortcut")

        await endActivity(status: "Copied")
        return output
    }

    // MARK: - Live Activity

    private func updateActivity(status: String) async {
        guard let activity else { return }
        await activity.update(ActivityContent(state: .init(status: status, startedAt: Date()), staleDate: nil))
    }

    private func endActivity(status: String) async {
        // Show the final state briefly, then auto-dismiss (the default policy lingers
        // for up to four hours / until the user swipes it away).
        await activity?.end(
            ActivityContent(state: .init(status: status, startedAt: Date()), staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(2.5))
        )
        activity = nil
    }

    private static func stateName(_ s: UIApplication.State) -> String {
        switch s {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "?"
        }
    }
}
