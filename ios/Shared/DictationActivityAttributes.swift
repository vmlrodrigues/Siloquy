import Foundation
import ActivityKit

/// Shared between the app (which starts/updates/ends the activity) and the widget
/// extension (which renders it in the Dynamic Island / on the Lock Screen).
struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Short status line, e.g. "Recording…", "Cleaning up…", "Copied".
        var status: String
        /// When recording began — drives the live timer in the Dynamic Island.
        var startedAt: Date
    }
}
