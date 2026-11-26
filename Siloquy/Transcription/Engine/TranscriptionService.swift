import Foundation

struct TranscriptionResult {
    let text: String
    /// The explicit language code used for this result, when the service can confirm it.
    let languageCode: String?
}

/// A protocol defining the interface for a transcription service.
/// This allows for a unified way to handle both local and cloud-based transcription models.
protocol TranscriptionService {
    /// Transcribes the audio from a given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to transcribe.
    ///   - model: The `TranscriptionModel` to use for transcription. This provides context about the provider (local, OpenAI, etc.).
    /// - Returns: The transcribed text as a `String`.
    /// - Throws: An error if the transcription fails.
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String
    func transcribeWithLanguage(audioURL: URL, model: any TranscriptionModel) async throws -> TranscriptionResult
}

extension TranscriptionService {
    func transcribeWithLanguage(audioURL: URL, model: any TranscriptionModel) async throws -> TranscriptionResult {
        let text = try await transcribe(audioURL: audioURL, model: model)
        return TranscriptionResult(text: text, languageCode: nil)
    }
}
