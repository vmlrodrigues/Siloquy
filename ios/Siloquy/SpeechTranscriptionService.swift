import Foundation
import Speech
import AVFoundation

/// On-device speech-to-text via iOS 26's SpeechAnalyzer / SpeechTranscriber.
/// Captures the mic with AVAudioEngine, feeds converted buffers into the
/// analyzer, and publishes a live (volatile) partial plus the finalized text.
@MainActor
final class SpeechTranscriptionService: ObservableObject {

    @Published private(set) var volatileText: String = ""
    @Published private(set) var finalizedText: String = ""
    @Published private(set) var isPreparingModel: Bool = false
    @Published private(set) var lastError: String?

    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private let audioEngine = AVAudioEngine()
    private var analyzerFormat: AVAudioFormat?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    /// Finalized text plus the current volatile fragment, for a live preview.
    var combinedText: String {
        switch (finalizedText.isEmpty, volatileText.isEmpty) {
        case (true, _):  return volatileText
        case (_, true):  return finalizedText
        default:         return finalizedText + " " + volatileText
        }
    }

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() async throws {
        finalizedText = ""
        volatileText = ""
        lastError = nil

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        try await ensureModelInstalled(for: transcriber)

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let piece = String(result.text.characters)
                    if result.isFinal {
                        self.appendFinal(piece)
                    } else {
                        self.volatileText = piece
                    }
                }
            } catch {
                self.lastError = error.localizedDescription
            }
        }

        try configureAudioSession()
        try startAudioEngine(target: analyzerFormat, continuation: continuation)
        try await analyzer.start(inputSequence: stream)
    }

    func stop() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        if !volatileText.isEmpty {
            appendFinal(volatileText)
            volatileText = ""
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func appendFinal(_ piece: String) {
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finalizedText = finalizedText.isEmpty ? trimmed : finalizedText + " " + trimmed
        volatileText = ""
    }

    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let target = locale.identifier(.bcp47)
        if installed.contains(where: { $0.identifier(.bcp47) == target }) { return }

        isPreparingModel = true
        defer { isPreparingModel = false }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Transcribe a recorded audio file on-device. The background dictation path
    /// records to a file (the live mic engine can't start backgrounded) and calls
    /// this on stop. Reuses the same on-device model as the live path — no extra
    /// permission prompt.
    func transcribeFile(_ url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        try await ensureModelInstalled(for: transcriber)

        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task { () -> String in
            var text = ""
            for try await result in transcriber.results {
                let piece = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { text = text.isEmpty ? piece : text + " " + piece }
            }
            return text
        }

        _ = try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return (try? await collector.value) ?? ""
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Installs the mic tap. The closure captures only local values (not `self`)
    /// so it can run on the realtime audio thread without actor hops.
    private func startAudioEngine(target: AVAudioFormat?,
                                  continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter: AVAudioConverter? = target.flatMap { AVAudioConverter(from: inputFormat, to: $0) }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let target, let converter else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = target.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

            var error: NSError?
            var supplied = false
            converter.convert(to: converted, error: &error) { _, statusPtr in
                if supplied { statusPtr.pointee = .noDataNow; return nil }
                supplied = true
                statusPtr.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}
