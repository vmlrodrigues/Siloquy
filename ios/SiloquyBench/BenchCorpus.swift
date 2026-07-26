import Foundation

/// Marker so we can find this test bundle at runtime — Swift Testing has no
/// XCTestCase class to hang `Bundle(for:)` off.
final class BenchBundleMarker {}

/// One raw dictation to clean. `id` is stable across runs so results can be
/// joined back to the source entry when reviewing diffs by hand.
struct CorpusItem: Codable, Sendable, Equatable {
    let id: String
    let rawText: String
}

/// The benchmark corpus.
///
/// Real dictation never lives in this repo. `Fixtures/corpus.json` is gitignored
/// and is produced by pulling the app's SwiftData store off the phone; when it is
/// absent — a fresh clone, CI, anyone but Victor — the benchmark still builds and
/// runs against the synthetic samples below, so the target never rots.
///
/// The synthetic set is *not* a substitute for real data. It exists to keep the
/// harness compiling and to smoke-test the plumbing. Any number quoted in a report
/// must come from the real corpus.
enum BenchCorpus {

    static func load() -> [CorpusItem] {
        guard let url = Bundle(for: BenchBundleMarker.self).url(forResource: "corpus", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([CorpusItem].self, from: data),
              !items.isEmpty
        else {
            return synthetic
        }
        return items
    }

    /// True when we're running against real dictation rather than the fallback.
    /// Reports must say which — the synthetic set is far too clean to be
    /// representative, and would flatter the model badly.
    static var isReal: Bool {
        Bundle(for: BenchBundleMarker.self).url(forResource: "corpus", withExtension: "json") != nil
    }

    /// Invented dictation with the disfluency patterns the prompt targets:
    /// fillers, false starts, doubled words, and a self-correction.
    static let synthetic: [CorpusItem] = [
        CorpusItem(
            id: "syn-01-fillers",
            rawText: "um so I was thinking that we could uh maybe move the meeting to like Tuesday afternoon if that works you know for everyone"
        ),
        CorpusItem(
            id: "syn-02-self-correction",
            rawText: "the delivery is booked for Tuesday sorry Wednesday morning and they said someone has to sign for it"
        ),
        CorpusItem(
            id: "syn-03-doubled-words",
            rawText: "I went to the the shop and and I picked up the thing we talked about yesterday it was cheaper than I expected"
        ),
        CorpusItem(
            id: "syn-04-false-start",
            rawText: "can you send me the— actually can you just send me the invoice for last month I need it for the accountant before Friday"
        ),
        CorpusItem(
            id: "syn-05-clean-short",
            rawText: "Remind me to call the dentist tomorrow morning."
        ),
        CorpusItem(
            id: "syn-06-long-rambling",
            rawText: "so the plan for the weekend is we drive up Saturday morning early hopefully before the traffic gets bad and then um we check in around noon I think check-in is noon or maybe one and then Sunday we could do the coastal walk if the weather holds otherwise there's that museum in town that everyone keeps saying is worth it and then drive back Sunday evening"
        )
    ]
}
