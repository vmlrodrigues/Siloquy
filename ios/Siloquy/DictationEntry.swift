import Foundation
import SwiftData

/// One saved dictation: the raw transcript plus the cleaned-up version.
@Model
final class DictationEntry {
    var createdAt: Date = Date()
    var rawText: String = ""
    var enhancedText: String = ""
    var usedEnhancement: Bool = false

    init(rawText: String, enhancedText: String, usedEnhancement: Bool) {
        self.createdAt = Date()
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.usedEnhancement = usedEnhancement
    }

    /// What to show/copy: the cleaned text when enhancement was used, else raw.
    var displayText: String {
        usedEnhancement && !enhancedText.isEmpty ? enhancedText : rawText
    }
}
