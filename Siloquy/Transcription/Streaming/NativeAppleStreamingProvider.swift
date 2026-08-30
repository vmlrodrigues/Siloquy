import AVFoundation
import Foundation
import os

#if canImport(Speech)
import Speech
#endif

/// Live transcription with Apple's SpeechAnalyzer.
///
/// Unlike Parakeet, which has no streaming mode and has to be coaxed into one by
/// re-transcribing overlapping windows and diffing the results, SpeechAnalyzer emits
/// partial results natively: ask for `.volatileResults` and every utterance arrives
/// first as a revisable guess and later as a final one. So this provider is mostly
/// plumbing — convert the recorder's PCM into the format the analyzer wants, and label
/// each result volatile or final.
final class NativeAppleStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "NativeAppleStreaming")
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    /// The recorder's format: 16 kHz, 16-bit signed, mono, little-endian.
    private static let inputSampleRate: Double = 16_000

    #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
    @available(macOS 26, *)
    private final class Session {
        let analyzer: SpeechAnalyzer
        let transcriber: SpeechTranscriber
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let analyzerFormat: AVAudioFormat
        var converter: AVAudioConverter?
        var resultsTask: Task<Void, Never>?

        init(
            analyzer: SpeechAnalyzer,
            transcriber: SpeechTranscriber,
            continuation: AsyncStream<AnalyzerInput>.Continuation,
            analyzerFormat: AVAudioFormat
        ) {
            self.analyzer = analyzer
            self.transcriber = transcriber
            self.continuation = continuation
            self.analyzerFormat = analyzerFormat
        }
    }

    /// Held as `Any` so the class itself doesn't require macOS 26.
    private var sessionBox: Any?

    @available(macOS 26, *)
    private var session: Session? {
        sessionBox as? Session
    }
    #endif

    /// Text the analyzer has finalised, joined for the running partial display.
    private var finalizedText = ""

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    // MARK: - StreamingTranscriptionProvider

    func connect(model: any TranscriptionModel, language: String?) async throws {
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        guard #available(macOS 26, *) else {
            throw StreamingTranscriptionError.connectionFailed("Apple Speech requires macOS 26 or later")
        }

        let locale = Locale(identifier: language ?? "en-US")
        let identifier = locale.identifier(.bcp47)

        let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        guard installed.contains(identifier) else {
            // Streaming has no way to prompt for a download mid-sentence, and falling
            // back to a different locale would silently transcribe the wrong language.
            throw StreamingTranscriptionError.connectionFailed(
                "Assets for \(identifier) are not downloaded"
            )
        }

        // Apple's own configuration for live display. Hand-picking `.volatileResults`
        // gets partial results but not the latency tuning that goes with the preset,
        // and the preset is what Apple keeps current.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

        await Self.reserveIfNeeded(locale: locale, transcriber: transcriber, logger: logger)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw StreamingTranscriptionError.connectionFailed("No audio format available for \(identifier)")
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let session = Session(
            analyzer: analyzer,
            transcriber: transcriber,
            continuation: continuation,
            analyzerFormat: analyzerFormat
        )
        sessionBox = session
        finalizedText = ""

        session.resultsTask = Task { [weak self] in
            await self?.consumeResults(from: transcriber)
        }

        try await analyzer.start(inputSequence: stream)

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Apple Speech streaming started for \(identifier, privacy: .public)")
        #else
        throw StreamingTranscriptionError.connectionFailed("Apple Speech is unavailable in this build")
        #endif
    }

    func sendAudioChunk(_ data: Data) async throws {
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        guard #available(macOS 26, *), let session else { return }
        guard let buffer = Self.makeBuffer(from: data, target: session.analyzerFormat, session: session) else { return }
        session.continuation.yield(AnalyzerInput(buffer: buffer))
        #endif
    }

    func commit() async throws {
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        guard #available(macOS 26, *), let session else {
            eventsContinuation?.yield(.committed(text: ""))
            return
        }

        session.continuation.finish()
        do {
            try await session.analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            logger.error("Finalize failed: \(error.localizedDescription, privacy: .public)")
        }

        // The results task ends when the analyzer closes the stream — but a finalize
        // that threw above never closes it, and nothing upstream times out this call, so
        // waiting unguarded loses the dictation and wedges the recorder. Cancel it if it
        // has not finished, and report whatever was finalised before the failure.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            session.resultsTask?.cancel()
        }
        await session.resultsTask?.value
        watchdog.cancel()

        eventsContinuation?.yield(.committed(text: finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)))
        #else
        eventsContinuation?.yield(.committed(text: ""))
        #endif
    }

    func disconnect() async {
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        if #available(macOS 26, *), let session {
            session.resultsTask?.cancel()
            session.continuation.finish()
            await session.analyzer.cancelAndFinishNow()
        }
        sessionBox = nil
        #endif
        finalizedText = ""
        eventsContinuation?.finish()
        logger.notice("Apple Speech streaming disconnected")
    }

    // MARK: - Private

    #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
    @available(macOS 26, *)
    private func consumeResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)

                if result.isFinal {
                    finalizedText += text
                    eventsContinuation?.yield(.partial(text: finalizedText))
                } else {
                    // Volatile: shown but not kept, since the next revision replaces it.
                    eventsContinuation?.yield(.partial(text: finalizedText + text))
                }
            }
        } catch {
            logger.error("Result stream failed: \(error.localizedDescription, privacy: .public)")
            eventsContinuation?.yield(.error(error))
        }
    }

    /// Claim this locale's reservation if it isn't already held.
    ///
    /// Deliberately does not release the others first. A reservation is what stops
    /// macOS reclaiming an installed locale, so releasing every other language to make
    /// room for this one uninstalls them — `DictationLanguageManager` owns the set and
    /// keeps every enabled language reserved. If the reservation cannot be taken the
    /// asset is already installed, so transcription proceeds regardless.
    @available(macOS 26, *)
    private static func reserveIfNeeded(locale: Locale, transcriber: SpeechTranscriber, logger: Logger) async {
        let identifier = locale.identifier(.bcp47)
        let reserved = await AssetInventory.reservedLocales
        guard !reserved.contains(where: { $0.identifier(.bcp47) == identifier }) else { return }

        do {
            _ = try await AssetInventory.reserve(locale: locale)
        } catch {
            logger.warning("Reservation failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Convert a chunk of the recorder's 16 kHz Int16 mono PCM into the analyzer's
    /// preferred format, which is chosen by the OS and is not the recorder's.
    @available(macOS 26, *)
    private static func makeBuffer(from data: Data, target: AVAudioFormat, session: Session) -> AVAudioPCMBuffer? {
        guard !data.isEmpty else { return nil }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: true
        ) else { return nil }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return nil
        }
        sourceBuffer.frameLength = frameCount

        guard let channel = sourceBuffer.int16ChannelData?[0] else { return nil }
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Int16.self).baseAddress else { return }
            channel.update(from: base, count: Int(frameCount))
        }

        if sourceFormat == target { return sourceBuffer }

        if session.converter == nil {
            session.converter = AVAudioConverter(from: sourceFormat, to: target)
        }
        guard let converter = session.converter else { return nil }

        let ratio = target.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }

        if conversionError != nil { return nil }
        return output.frameLength > 0 ? output : nil
    }
    #endif
}
