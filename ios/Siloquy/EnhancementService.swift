import Foundation
import FoundationModels

/// Structured output: forces the model to return ONLY the cleaned text
/// (no "Sure, here's…" preamble). File-scoped so the @Generable-synthesized
/// conformance can access it.
@Generable
fileprivate struct CleanedDictation {
    @Guide(description: "The dictation rewritten as clean, natural text: filler words and false starts removed, accidental repeated words collapsed, grammar/spelling/punctuation fixed, self-corrections applied. Plain text only — no quotes, no commentary, no explanation.")
    var cleanedText: String
}

/// Cleans up dictated text with Apple's on-device Foundation Model.
///
/// Uses *guided generation* so the model returns only the cleaned text (no
/// "Sure, here's…" preamble), and always degrades gracefully: if the model is
/// unavailable, throws a guardrail error, or emits an assistant-style refusal,
/// the raw transcript is returned unchanged — your words are never lost or
/// replaced with an apology.
@MainActor
final class EnhancementService {

    enum Status {
        case available
        case unavailable(String)
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable("This iPhone doesn't support Apple Intelligence — cleanup is off, but raw transcripts still work.")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Turn on Apple Intelligence in Settings to enable cleanup.")
            case .modelNotReady:
                return .unavailable("The on-device model is still preparing — cleanup will switch on shortly.")
            @unknown default:
                return .unavailable("On-device cleanup is unavailable right now.")
            }
        }
    }

    static var unavailableMessage: String? {
        if case .unavailable(let message) = status { return message }
        return nil
    }

    private static let instructions = """
    You are a text-cleanup function for dictation — not a chat assistant. You \
    receive a raw speech-to-text transcript and rewrite it so it reads as if it \
    were carefully typed.

    Rules:
    - Remove filler words (um, uh, like, you know), stutters, and false starts.
    - Collapse accidental repeated words or phrases (e.g. "and see and see" -> "and see").
    - Fix grammar, spelling, and punctuation.
    - Apply self-corrections, keeping only the final intended version (e.g. "Tuesday, \
    sorry, Wednesday" -> "Wednesday").
    - Preserve the speaker's words, tone, meaning, and any strong or explicit \
    language exactly. Do not censor, soften, moralize, or refuse.
    - Never explain what you are doing and never converse. Return ONLY the cleaned \
    text in `cleanedText`.
    """

    /// Transcripts at least this long get a second attempt when the first comes back
    /// unchanged. The model is markedly non-deterministic on longer dictation — across three
    /// identical runs over 29 real transcripts, 38% of items changed outcome and *none* was
    /// cleaned in all three — so an unchanged result is often a bad roll rather than
    /// "nothing to clean". Below this length unchanged is nearly always right (the
    /// consistently-unchanged transcripts averaged 65 characters and carried no disfluency),
    /// so retrying there would only cost latency.
    ///
    /// Measured over those same 29 transcripts: retrying lifted the mean cleaned count from
    /// 5.0 to 10.3.
    private static let retryThreshold = 80

    /// Returns the cleaned text, or the original text unchanged on any failure.
    func enhance(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard case .available = Self.status else { return text }

        if let cleaned = await attempt(trimmed), cleaned != trimmed {
            return cleaned
        }

        // Unchanged, refused, or thrown. On a substantial transcript that earns one more
        // roll — which also covers the intermittent `exceededContextWindowSize` the model
        // raises on some short self-corrections.
        guard trimmed.count >= Self.retryThreshold else { return text }
        if let retried = await attempt(trimmed), retried != trimmed {
            return retried
        }
        return text
    }

    /// One generation attempt. Returns nil if the model threw, refused, or produced nothing;
    /// the dictation is never failed — the caller hands back the raw transcript, uncensored.
    private func attempt(_ trimmed: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: "Dictation to clean:\n\n\(trimmed)",
                generating: CleanedDictation.self
            )
            let cleaned = response.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty || Self.looksLikeRefusal(cleaned) { return nil }
            return cleaned
        } catch {
            // guardrailViolation, context-window, etc.
            return nil
        }
    }

    /// High-precision detector for assistant-style refusals that occasionally land
    /// in the output instead of being thrown. These phrases don't occur in natural
    /// dictation, so matching them is safe against false positives.
    private static func looksLikeRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "as an ai",
            "i cannot complete",
            "i can't complete this request",
            "i'm unable to complete",
            "i am unable to complete",
            "i cannot fulfill",
            "i cannot assist with",
            "i cannot create",
            "cannot complete requests that contain",
            "would you like me to complete this request",
            "i cannot generate"
        ]
        return markers.contains { lower.contains($0) }
    }
}
