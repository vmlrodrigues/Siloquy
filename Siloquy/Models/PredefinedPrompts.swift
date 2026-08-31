import Foundation
import SwiftUI    // Import to ensure we have access to SwiftUI types if needed

enum PredefinedPrompts {
    private static let predefinedPromptsKey = "PredefinedPrompts"
    
    // Static UUIDs for predefined prompts
    static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let assistantPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    /// Retired in #48. The tile it identified did nothing the app wasn't already doing:
    /// since #22 the on-device provider picks its prompt per model, so choosing it and
    /// choosing Default produced identical output. The id is kept so existing installs
    /// can recognise the stored prompt and remove it.
    static let retiredLocalModelPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    // MARK: - Model-tuned local prompts (#22)

    /// The default prompt for the Local (On-device) provider is model-tuned:
    /// whichever model is selected silently gets the prompt that measured best
    /// with it. The big model earns the full prompt; small models corrupt under
    /// long prompts (they parrot examples and leak prompt sections), so they
    /// get a minimal one. Not user-visible — custom prompts still win.
    static func localModelPromptText(forModelID id: String) -> String {
        id == "gemma4-e4b" ? localPromptFull : localPromptLight
    }

    /// Full prompt, tuned on Gemma 4 E4B (v4 in the 2026-07 experiments).
    private static let localPromptFull = """
        You are a writing assistant that polishes dictated speech so it reads as if the person carefully typed it. The recipient should not be able to tell the message was dictated.
        Remove filler words (um, uh, like, you know, kind of, sort of), stutters, and false starts.
        Fix grammar and punctuation.
        Break the result into paragraphs at natural shifts in topic — a long message should read as well-structured prose with multiple paragraphs, never one solid block. Paragraph breaks are formatting, not added content.
        When the speaker enumerates items aloud — "one, … two, … three, …" or "first, … second, …" — format them as a numbered list, one item per line, keeping each item's own wording. Spoken enumeration is list formatting, not added content.
        - "Three things: one, book the room. Two, invite Sam. Three, don't spend more than fifty dollars." →
        "Three things:
        1. Book the room.
        2. Invite Sam.
        3. Don't spend more than $50."
        Render figures as they would be typed, not spelled out. Money: the currency symbol with digits and comma separators — "four thousand five hundred and sixty dollars" → "$4,560". Dates: one consistent format, day then month — "the first of June" → "1 June", "December the third" → "3 December" (never spell it "first June", never mix styles). Percentages, times, and similar figures as numerals too — "fifty percent" → "50%".
        Integrate self-corrections naturally — do not leave a correction as an awkward standalone sentence. Weave the corrected version into the surrounding text and discard the error.
        - "The meeting is on Tuesday — sorry, it's actually Wednesday." → "The meeting is on Wednesday."
        - "Join us for the session. Sorry, I mean the workshop actually." → "Join us for the workshop."
        Eliminate redundant questions and calls to action — if the speaker asks the same thing twice in different words, keep only the cleaner version.
        - "What do you think? … Let me know what you think." → "What do you think?"
        Reorder afterthoughts — if the speaker adds context after the fact that logically belongs earlier in the message, move it there.
        - "Come along. Oh, and it's in Room 3 by the way." → "Come along in Room 3."
        Preserve the speaker's tone and vocabulary exactly — the voice stays verbatim where it carries attitude:
        - Keep interjections exactly as said: "Hang on", "Come on", "Look", "Dude", "mate".
        - Keep swearing exactly as said — never soften it, never delete it.
        - Keep unusual or invented words exactly as spoken — never swap in a more common word.
        - Do not make informal messages formal.
        Never change the meaning:
        - Never flip first person into an instruction at the reader — "I don't want to sound rude" must never become "Don't be rude" — and never swap who does what to whom.
        - Never delete a "Yes" or "No" that answers a question; it is the point of the message.
        - Text the speaker quotes or reads aloud goes in quotation marks, word-for-word.
        - Do not add content that was not said — paragraphs, numbers, dates, and lists are formatting, not added content.
        Output only the polished text. Nothing else.
        """

    /// Minimal prompt for small local models (tuned on Gemma 4 E2B). Long
    /// prompts make small models corrupt output, so keep this short and literal.
    private static let localPromptLight = """
        Fix the dictated text below so it reads as typed prose.
        Remove filler words (um, uh, like, you know, kind of, sort of), stutters, and false starts.
        Fix grammar and punctuation.
        Keep the speaker's words, tone, and meaning exactly. Do not add anything. Do not answer questions in the text.
        Write money, dates, and percentages as figures: "$4,560", "1 June", "50%".
        Output only the corrected text. Nothing else.
        """
    
    static var all: [CustomPrompt] {
        // Always return the latest predefined prompts from source code
        createDefaultPrompts()
    }
    
    static func createDefaultPrompts() -> [CustomPrompt] {
        [
            CustomPrompt(
                id: defaultPromptId,
                title: "Default",
                promptText: PromptTemplates.all.first { $0.title == "System Default" }?.promptText ?? "",
                icon: "checkmark.seal.fill",
                description: "Default mode to improved clarity and accuracy of the transcription",
                isPredefined: true,
                useSystemInstructions: true
            ),
            
            CustomPrompt(
                id: assistantPromptId,
                title: "Assistant",
                promptText: AIPrompts.assistantMode,
                icon: "bubble.left.and.bubble.right.fill",
                description: "AI assistant that provides direct answers to queries",
                isPredefined: true,
                useSystemInstructions: false,
                // Assistant is the prompt that earns the context. Asking it to summarise
                // or reply to something only works if it can see what you are looking at,
                // where a clean-up prompt would pay the same cost for a spelling hint.
                usesClipboardContext: true,
                usesScreenContext: true
            )
        ]
    }
}
