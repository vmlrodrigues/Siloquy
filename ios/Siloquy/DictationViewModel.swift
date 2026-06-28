import SwiftUI
import SwiftData
import Combine
import UIKit

/// Drives the whole loop: record → transcribe → (optional) clean → save → copy.
@MainActor
final class DictationViewModel: ObservableObject {

    @Published var isRecording = false
    @Published var isEnhancing = false
    @Published var enhancementEnabled = true
    @Published var result: String = ""
    @Published var statusMessage: String?

    let transcription = SpeechTranscriptionService()
    private let enhancement = EnhancementService()
    private var cancellable: AnyCancellable?

    init() {
        // Re-publish the transcription service's live updates so views observing
        // this view model refresh as partial results stream in.
        cancellable = transcription.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var liveText: String { transcription.combinedText }
    var isPreparingModel: Bool { transcription.isPreparingModel }

    func toggle(context: ModelContext) async {
        if isRecording {
            await stopAndProcess(context: context)
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        result = ""
        statusMessage = nil

        let granted = await SpeechTranscriptionService.requestMicrophonePermission()
        guard granted else {
            statusMessage = "Microphone access is needed — enable it in Settings."
            return
        }

        do {
            try await transcription.start()
            isRecording = true
        } catch {
            statusMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func stopAndProcess(context: ModelContext) async {
        await transcription.stop()
        isRecording = false

        let raw = transcription.finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            statusMessage = "Didn't catch anything — try again."
            return
        }

        var output = raw
        var used = false
        if enhancementEnabled {
            isEnhancing = true
            output = await enhancement.enhance(raw)
            used = (output != raw)
            isEnhancing = false
        }

        result = output
        UIPasteboard.general.string = output
        context.insert(DictationEntry(rawText: raw, enhancedText: output, usedEnhancement: used))
        statusMessage = "Copied to clipboard."
    }
}
