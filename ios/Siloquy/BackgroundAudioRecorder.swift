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

    /// Start recording. The first background `record()` is reliable once `prime()` has
    /// warmed the pipeline in the foreground; the retry below covers the occasional miss.
    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bg-dictation.m4a")
        try? FileManager.default.removeItem(at: url)

        func attempt() -> Bool {
            guard let r = try? AVAudioRecorder(url: url, settings: Self.settings), r.record() else { return false }
            recorder = r
            fileURL = url
            return true
        }

        // record() occasionally returns false on the first try right after the session
        // activates; retry with growing settle gaps to catch it.
        if attempt() { return }
        for delayMs in [250, 600, 1200] {
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            if attempt() { return }
        }
        throw RecorderError.couldNotStart(
            "inputAvail=\(session.isInputAvailable) otherAudio=\(session.isOtherAudioPlaying)")
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
