import Foundation
import FoundationModels
import Testing
@testable import Siloquy

/// Why does the on-device model refuse 5.7% of real dictation?
///
/// The baseline run found six refusals, none containing profanity or explicit
/// material. Two concern song lyrics — but nobody asked the model *for* lyrics, and
/// cleaning those transcripts returns roughly the same sentence, so "copyright
/// guardrail" does not explain it on its own.
///
/// The hypothesis this probe tests: the model is **escaping the cleanup task and
/// answering the dictation as a prompt**. Four of the six refused transcripts are
/// questions or commands ("Find me a song with…", "What would I need to do?"), against
/// 30% of the corpus at large. If the model tries to *answer* those, the answer is what
/// trips the guardrail — actual lyrics, actual medical advice — and the refusal has
/// nothing to do with the words the user dictated.
///
/// Decisive test: harden the instruction/data boundary and see if the refusals clear.
/// If they do, the cause is task escape and the fix is prompt-shaped. If they don't,
/// the guardrail is reacting to the input itself and needs a different answer entirely.
struct RefusalProbe {

    /// The six that threw in the 26 July baseline run.
    static let refusedIDs = ["pk51", "pk58", "pk60", "pk70", "pk80", "pk106"]
    static let repeats = 3

    @Test("refusal probe — task escape or content?")
    func probe() async throws {
        let items = BenchCorpus.load().filter { Self.refusedIDs.contains($0.id) }
        try #require(!items.isEmpty, "corpus fixture missing — probe needs the real transcripts")

        print("\n═══ REFUSAL PROBE ═══ \(items.count) transcripts × \(Self.repeats) repeats × \(PromptVariant.allCases.count) variants")

        for variant in PromptVariant.allCases {
            var refusedTotal = 0
            var attempts = 0

            for item in items {
                var refused = 0
                for _ in 0..<Self.repeats {
                    attempts += 1
                    let session = LanguageModelSession(instructions: variant.instructions)
                    do {
                        _ = try await session.respond(
                            to: variant.prompt(item.rawText),
                            generating: CleanedDictation.self
                        )
                    } catch {
                        refused += 1
                        refusedTotal += 1
                    }
                }
                print("PROBE \(variant.rawValue) \(item.id) refused=\(refused)/\(Self.repeats)")
            }

            print("PROBE TOTAL \(variant.rawValue): \(refusedTotal)/\(attempts) refused\n")
        }
    }
}
