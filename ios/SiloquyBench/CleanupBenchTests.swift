import Evaluations
import Foundation
import TabularData
import Testing

/// The iOS 27 on-device cleanup benchmark — issue #39.
///
/// Not a pass/fail test suite. Nothing here gates a build: these are measurements,
/// and a "failing" determinism metric is a finding, not a broken test. The only
/// assertion is that the run produced data at all.
///
/// Run it on the phone, never the simulator — simulator timings are host-Mac speed
/// and say nothing about what a dictation feels like on an A19 Pro:
///
///     DEVELOPER_DIR=<Xcode 27 beta>.app/Contents/Developer \
///     xcodebuild test -project Siloquy.xcodeproj -scheme Siloquy \
///       -destination 'platform=iOS,id=<udid>' -only-testing:SiloquyBench
///
/// The beta toolchain is reached via DEVELOPER_DIR on purpose — `xcode-select`
/// stays on stable Xcode so the macOS app's release path never picks up a beta.
///
@Suite("iOS 27 on-device cleanup", .serialized)
struct CleanupBenchTests {

    /// Three runs of the same input is the minimum that can see the defect at all —
    /// issue #38 measured 38% of items changing outcome between identical runs.
    static let repeats = 3
    static let items = BenchCorpus.load()

    static var info: [String: String] {
        [
            "corpus": BenchCorpus.isReal ? "real" : "synthetic",
            "corpus_size": String(items.count),
            "repeats": String(repeats),
            "device": ProcessInfo.processInfo.operatingSystemVersionString
        ]
    }

    @Test("baseline — as the app calls it today",
          .evaluates(CleanupEvaluation(condition: .baseline, repeats: repeats, items: items), info: info))
    func baseline() throws { try Self.record(.baseline) }

    @Test("reasoningLevel .light",
          .evaluates(CleanupEvaluation(condition: .light, repeats: repeats, items: items), info: info))
    func light() throws { try Self.record(.light) }

    @Test("reasoningLevel .moderate",
          .evaluates(CleanupEvaluation(condition: .moderate, repeats: repeats, items: items), info: info))
    func moderate() throws { try Self.record(.moderate) }

    @Test("reasoningLevel .deep",
          .evaluates(CleanupEvaluation(condition: .deep, repeats: repeats, items: items), info: info))
    func deep() throws { try Self.record(.deep) }

    // MARK: -

    /// Pulls the finished evaluation off `EvaluationContext`, prints it into the
    /// xcodebuild log, and writes the per-sample table into the app container so it
    /// can be pulled off the phone for the write-up.
    private static func record(_ condition: BenchCondition) throws {
        let result = EvaluationContext.current.result

        print("""

        ══════════ \(condition.rawValue) ══════════
        corpus: \(BenchCorpus.isReal ? "real" : "SYNTHETIC — not reportable") (\(items.count) items × \(repeats) repeats)
        duration: \(String(format: "%.1f", result.duration))s

        \(result.groupedSummary)
        """)

        // The headline figures, restated plainly so they're greppable in CI logs.
        let deterministic = result.aggregateValue(.mean(of: Metric(MetricName.deterministic)))
        let changed = result.aggregateValue(.mean(of: Metric(MetricName.changed)))
        let meanLatency = result.aggregateValue(.mean(of: Metric(MetricName.latency)))
        let sdLatency = result.aggregateValue(.standardDeviation(of: Metric(MetricName.latency)))
        let maxLatency = result.aggregateValue(.maximum(of: Metric(MetricName.latency)))
        let reasoning = result.aggregateValue(.mean(of: Metric(MetricName.reasoningTokens)))

        print("""
        RESULT \(condition.rawValue) \
        deterministic=\(pct(deterministic)) \
        changed=\(pct(changed)) \
        latency_mean=\(String(format: "%.2f", meanLatency))s \
        latency_sd=\(String(format: "%.2f", sdLatency))s \
        latency_max=\(String(format: "%.2f", maxLatency))s \
        reasoning_tokens=\(String(format: "%.0f", reasoning))

        """)

        try write(result.detailed, named: "\(condition.rawValue)-detailed.csv")
        try write(result.summary, named: "\(condition.rawValue)-summary.csv")

        #expect(items.isEmpty == false, "corpus was empty — nothing was measured")
    }

    private static func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    /// Writes into the host app's Documents directory. Retrieve with:
    ///
    ///     xcrun devicectl device copy from --device <udid> \
    ///       --domain-type appDataContainer \
    ///       --domain-identifier com.victorrodrigues.siloquy.ios \
    ///       --source Documents/bench --destination ./out
    private static func write(_ frame: DataFrame, named name: String) throws {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let directory = documents.appendingPathComponent("bench", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try frame.writeCSV(to: directory.appendingPathComponent(name))
    }
}
