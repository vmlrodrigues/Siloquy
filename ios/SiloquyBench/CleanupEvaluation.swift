import Evaluations
import Foundation
import FoundationModels
@testable import Siloquy

/// The conditions under test.
///
/// `baseline` is the iOS 27 on-device model called exactly as the shipping app
/// calls it — no `reasoningLevel` — and is the number that matters for "should we
/// change anything". The three reasoning levels are new in iOS 27 and are the open
/// question: `ContextOptions` is model-agnostic in the API, but whether the
/// *on-device* model does anything with it is unknown until measured.
///
/// There is no iOS 26 condition here. That phone is on 27 and cannot go back; the
/// iOS 26 baseline comes from the issue #38 study and must be quoted as a separate,
/// differently-measured figure — not folded into these results.
enum BenchCondition: String, CaseIterable, Sendable {
    case baseline
    case light
    case moderate
    case deep

    var reasoningLevel: ContextOptions.ReasoningLevel? {
        switch self {
        case .baseline: return nil
        case .light:    return .light
        case .moderate: return .moderate
        case .deep:     return .deep
        }
    }
}

/// What one sample produced across all its repeats.
///
/// Everything the evaluators need lives here — including `raw` — so no evaluator
/// has to reach back into the sample or rely on an `expected` value. There is no
/// ground truth for this task: nobody has hand-written the "correct" cleanup for
/// each transcript, so the measurements are all self-relative (did it change, did
/// it change *consistently*, what did it cost).
struct CleanupOutcome: Codable, Sendable, Equatable {
    var raw: String
    var texts: [String] = []
    var seconds: [Double] = []
    var inputTokens: [Int] = []
    var outputTokens: [Int] = []
    var reasoningTokens: [Int] = []
    /// Repeats where the model threw — guardrail violation, context overflow, etc.
    var failures: Int = 0
    /// Why they threw. Kept verbatim: an unsupported-option error and a guardrail
    /// refusal are completely different findings, and collapsing both into a count
    /// throws away the answer.
    var errors: [String] = []
    /// How many times a call was throttled and retried. Not a failure — but if this is
    /// large the run was fighting the rate limiter and its latency figures are suspect.
    var rateLimitWaits: Int = 0

    /// How many *different* answers the model gave to the same input. This is the
    /// headline number: issue #38 found that on iOS 26 the model would clean a
    /// transcript or return it verbatim more or less at random, and that no amount
    /// of prompt work fixed it. 1 means stable.
    var distinctTexts: Int { Set(texts).count }

    /// Stable *and* never threw across every repeat.
    var isDeterministic: Bool { failures == 0 && distinctTexts == 1 }

    /// Fraction of successful repeats that actually altered the transcript. The app
    /// records the same signal per dictation as `usedEnhancement`.
    var changedFraction: Double {
        guard !texts.isEmpty else { return 0 }
        return Double(texts.filter { $0 != raw }.count) / Double(texts.count)
    }

    var meanSeconds: Double {
        guard !seconds.isEmpty else { return 0 }
        return seconds.reduce(0, +) / Double(seconds.count)
    }

    var meanOutputTokensPerSecond: Double {
        guard !seconds.isEmpty, !outputTokens.isEmpty else { return 0 }
        let totalTokens = Double(outputTokens.reduce(0, +))
        let totalSeconds = seconds.reduce(0, +)
        guard totalSeconds > 0 else { return 0 }
        return totalTokens / totalSeconds
    }

    var meanReasoningTokens: Double {
        guard !reasoningTokens.isEmpty else { return 0 }
        return Double(reasoningTokens.reduce(0, +)) / Double(reasoningTokens.count)
    }
}

/// One transcript to clean.
struct CleanupSample: SampleProtocol {
    typealias ExpectedValue = CleanupOutcome

    let item: CorpusItem

    var input: String { item.rawText }
    /// Deliberately nil — see `CleanupOutcome`. There is no reference answer.
    var expected: CleanupOutcome? { nil }
}

// MARK: - Evaluation

/// Runs the app's *exact* cleanup call over the corpus, N times per transcript,
/// under one condition.
///
/// Fidelity matters more than convenience here: the instructions, the `@Generable`
/// schema and the prompt wording are taken from `EnhancementService` rather than
/// copied, and a fresh `LanguageModelSession` is created per repeat because that is
/// what the shipping code does. The one thing deliberately *not* reproduced is
/// `EnhancementService.enhance`'s retry — that retry is the workaround this study
/// exists to re-examine, so measuring through it would hide the answer.
struct CleanupEvaluation: Evaluation {
    typealias Sample = CleanupSample
    typealias Subject = ModelSubject<CleanupOutcome>

    /// Rate-limit backoff is 2s doubling; six attempts covers about a minute of
    /// throttling before a call is finally given up on.
    static let maxRateLimitRetries = 6

    let condition: BenchCondition
    let variant: PromptVariant
    let repeats: Int
    let items: [CorpusItem]

    var name: String { "cleanup-\(variant.rawValue)-\(condition.rawValue)" }

    var dataset: ArrayLoader<CleanupSample> {
        ArrayLoader(samples: items.map(CleanupSample.init))
    }

    func subject(from sample: CleanupSample) async throws -> ModelSubject<CleanupOutcome> {
        var outcome = CleanupOutcome(raw: sample.item.rawText)
        let clock = ContinuousClock()

        for repeatIndex in 0..<repeats {
            // A run of several hundred calls trips the model's rate limiter. That is a
            // property of hammering it in a loop, not of the prompt under test, so it
            // must never land in `failures` — a throttled run once looked like a
            // catastrophic prompt regression (223 "refusals") when nothing was wrong.
            // Pace the calls, and back off rather than record a result.
            if repeatIndex > 0 { try? await Task.sleep(for: .milliseconds(150)) }

            var backoff = Duration.seconds(2)
            var settled = false

            for attempt in 0..<Self.maxRateLimitRetries {
                // Fresh session per attempt — matches `EnhancementService.attempt`, and
                // keeps repeats independent rather than letting one prime the next.
                let session = LanguageModelSession(instructions: variant.instructions)
                let start = clock.now
                do {
                    let response = try await session.respond(
                        to: variant.prompt(sample.item.rawText),
                        generating: CleanedDictation.self,
                        // `includeSchemaInPrompt: true` is the default for the
                        // schema-generating overloads. Passing ContextOptions replaces
                        // that default wholesale, so it has to be restated or the
                        // reasoning conditions would silently differ from baseline in a
                        // second way and confound the comparison.
                        contextOptions: ContextOptions(
                            includeSchemaInPrompt: true,
                            reasoningLevel: condition.reasoningLevel
                        )
                    )
                    outcome.seconds.append(Self.seconds(clock.now - start))
                    outcome.texts.append(
                        response.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    outcome.inputTokens.append(response.usage.input.totalTokenCount)
                    outcome.outputTokens.append(response.usage.output.totalTokenCount)
                    outcome.reasoningTokens.append(response.usage.output.reasoningTokenCount)
                    settled = true
                } catch let error as LanguageModelError {
                    if case .rateLimited = error, attempt < Self.maxRateLimitRetries - 1 {
                        outcome.rateLimitWaits += 1
                        try? await Task.sleep(for: backoff)
                        backoff *= 2
                        continue
                    }
                    outcome.failures += 1
                    outcome.errors.append(String(describing: error))
                    settled = true
                } catch {
                    outcome.failures += 1
                    outcome.errors.append(String(describing: error))
                    settled = true
                }
                if settled { break }
            }

            if !settled {
                outcome.failures += 1
                outcome.errors.append("rate limited through \(Self.maxRateLimitRetries) attempts")
            }
        }

        // Printed per sample rather than collected at the end: a full matrix run is
        // long, and if a condition is going to fail we want to know on sample one,
        // not forty minutes later. It also survives the test body being skipped when
        // the framework throws during aggregation.
        print("BENCH \(variant.rawValue) \(sample.item.id) "
              + "distinct=\(outcome.distinctTexts) failures=\(outcome.failures) "
              + "mean=\(String(format: "%.2f", outcome.meanSeconds))s"
              + (outcome.rateLimitWaits > 0 ? " throttled=\(outcome.rateLimitWaits)" : "")
              + (outcome.errors.isEmpty ? "" : " ERROR=\(outcome.errors[0])"))

        return ModelSubject(value: outcome)
    }

    @EvaluatorsBuilder<CleanupSample, ModelSubject<CleanupOutcome>>
    var evaluators: Evaluators {
        DeterminismEvaluator()
        CleanupRateEvaluator()
        CostEvaluator()
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Metric(MetricName.deterministic))
        aggregator.computeMean(of: Metric(MetricName.distinctOutputs))
        aggregator.computeMean(of: Metric(MetricName.changed))
        aggregator.computeMean(of: Metric(MetricName.failed))

        aggregator.computeMean(of: Metric(MetricName.latency))
        aggregator.computeMedian(of: Metric(MetricName.latency))
        aggregator.computeMaximum(of: Metric(MetricName.latency))
        // Spread matters as much as the average: a model that is usually fast and
        // occasionally awful is a worse dictation experience than a steady one.
        aggregator.computeStandardDeviation(of: Metric(MetricName.latency))

        aggregator.computeMean(of: Metric(MetricName.tokensPerSecond))
        aggregator.computeMean(of: Metric(MetricName.reasoningTokens))
    }

    private static func seconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) + Double(c.attoseconds) * 1e-18
    }
}

// MARK: - Metrics

enum MetricName {
    static let deterministic = "deterministic"
    static let distinctOutputs = "distinct_outputs"
    static let changed = "changed"
    static let failed = "failed"
    static let latency = "latency_s"
    static let tokensPerSecond = "tokens_per_s"
    static let reasoningTokens = "reasoning_tokens"
}

/// The reason this study exists.
struct DeterminismEvaluator: EvaluatorProtocol {
    func metrics(subject: ModelSubject<CleanupOutcome>, input: CleanupSample) async throws -> [Metric] {
        let outcome = subject.value
        let determinism = Metric(MetricName.deterministic)
        return [
            outcome.isDeterministic
                ? determinism.passing(rationale: "identical across all repeats")
                : determinism.failing(rationale: "\(outcome.distinctTexts) distinct outputs, \(outcome.failures) failures"),
            Metric(MetricName.distinctOutputs).scoring(Double(outcome.distinctTexts))
        ]
    }
}

/// Did it clean anything, and did it survive?
struct CleanupRateEvaluator: EvaluatorProtocol {
    func metrics(subject: ModelSubject<CleanupOutcome>, input: CleanupSample) async throws -> [Metric] {
        let outcome = subject.value
        let attempts = outcome.texts.count + outcome.failures
        let failedFraction = attempts == 0 ? 0 : Double(outcome.failures) / Double(attempts)
        return [
            Metric(MetricName.changed).scoring(
                outcome.changedFraction,
                rationale: "\(Int(outcome.changedFraction * 100))% of repeats altered the transcript"
            ),
            Metric(MetricName.failed).scoring(failedFraction)
        ]
    }
}

/// What it costs. Latency is the one the user actually feels.
struct CostEvaluator: EvaluatorProtocol {
    func metrics(subject: ModelSubject<CleanupOutcome>, input: CleanupSample) async throws -> [Metric] {
        let outcome = subject.value
        return [
            Metric(MetricName.latency).scoring(outcome.meanSeconds),
            Metric(MetricName.tokensPerSecond).scoring(outcome.meanOutputTokensPerSecond),
            Metric(MetricName.reasoningTokens).scoring(outcome.meanReasoningTokens)
        ]
    }
}
