import Foundation
import AVFoundation

/// File-based background recording. `AVAudioRecorder` is a higher-level path than the
/// live `AVAudioEngine` input node and — under an `AudioRecordingIntent` — can open the
/// mic from a cold background launch (where the live engine fails with a HAL "mic
/// unavailable" error). Records to a file; transcribed on stop.
@MainActor
final class BackgroundAudioRecorder {
    enum RecorderError: LocalizedError {
        case couldNotStart(String)
        var errorDescription: String? {
            switch self { case .couldNotStart(let info): return "record() returned false (\(info))" }
        }
    }

    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,          // 16 kHz mono is ample for speech
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    private static var recordPermissionString: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "granted"
        case .denied: return "denied"
        case .undetermined: return "undetermined"
        @unknown default: return "?"
        }
    }

    /// Warm the mic pipeline in the foreground (called when the app is active) with a
    /// brief throwaway recording, so the first real background `record()` doesn't have
    /// to cold-start the hardware — which is intermittently slow (seconds) to settle.
    func prime() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let warmURL = FileManager.default.temporaryDirectory.appendingPathComponent("warm.m4a")
        try? FileManager.default.removeItem(at: warmURL)
        if let r = try? AVAudioRecorder(url: warmURL, settings: Self.settings), r.record() {
            try? await Task.sleep(nanoseconds: 250_000_000)
            r.stop()
        }
        try? FileManager.default.removeItem(at: warmURL)
        try? session.setActive(false)
    }

    /// Start recording. `prepareToRecord()` pre-arms the mic hardware; the retry loop
    /// re-activates the session between tries, because the usual background failure is the
    /// session coming up half-ready and a bare `record()` retry on the same half-ready
    /// session never recovers. On exhaustion it throws a rich diagnostic (route, permission,
    /// prepared/reactivation state) so a later log pull reveals the cause without a live
    /// capture.
    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bg-dictation.m4a")
        try? FileManager.default.removeItem(at: url)

        var lastPrepared = false          // captured for the failure diagnostic
        var reactivateError: String?

        func attempt() -> Bool {
            guard let r = try? AVAudioRecorder(url: url, settings: Self.settings) else { return false }
            // prepareToRecord() pre-allocates the mic hardware; record() alone must do that
            // synchronously and is likelier to bail if the input route hasn't settled
            // (e.g. a Bluetooth HFP mic coming up in the background).
            lastPrepared = r.prepareToRecord()
            guard r.record() else { return false }
            recorder = r
            fileURL = url
            return true
        }

        if attempt() { return }
        for delayMs in [250, 600, 1200] {
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            // A bare record() retry on the same half-ready session never recovers, so cycle
            // the session to give the input route a clean second chance. Deactivate is
            // best-effort; the reactivation error is the one that matters (and gets logged).
            try? session.setActive(false)
            do {
                try session.setActive(true)
                reactivateError = nil
            } catch {
                reactivateError = error.localizedDescription
            }
            if attempt() { return }
        }

        let route = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        throw RecorderError.couldNotStart(
            "inputAvail=\(session.isInputAvailable) otherAudio=\(session.isOtherAudioPlaying) "
            + "prepared=\(lastPrepared) route=[\(route.isEmpty ? "none" : route)] "
            + "perm=\(Self.recordPermissionString) reactivateErr=\(reactivateError ?? "none")")
    }

    /// Stops recording; returns the file URL and its byte size.
    @discardableResult
    func stop() -> (url: URL?, bytes: Int) {
        recorder?.stop()
        recorder = nil
        guard let url = fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return (fileURL, 0) }
        return (url, size)
    }

    /// Deactivate the shared session — a toggle/stop runs as an `AudioRecordingIntent`,
    /// which must not end with an active session and no Live Activity.
    func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
