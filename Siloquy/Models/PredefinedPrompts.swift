import Foundation
import SwiftUI    // Import to ensure we have access to SwiftUI types if needed

enum PredefinedPrompts {
    private static let predefinedPromptsKey = "PredefinedPrompts"
    
    // Static UUIDs for predefined prompts
    static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let assistantPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let localModelPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    
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
                useSystemInstructions: false
            ),

            CustomPrompt(
                id: localModelPromptId,
                title: "Local Model Default",
                promptText: """
                    - Remove filler words (um, uh, like, you know, kind of, sort of), stutters, and false starts.
                    - Fix grammar and spelling errors. Do not change meaning, word choice, or sentence structure beyond what grammar requires.
                    - Handle self-corrections: keep only the final intended version. Applies to:
                      - Explicit signals: "scratch that", "actually", "no wait", "sorry", "I mean", "hang on", "let me rephrase", "I meant"
                      - Implicit restarts: when a sentence trails off and is restarted — keep only the restarted version
                      - "The meeting is on Tuesday, sorry, actually Wednesday" → "The meeting is on Wednesday."
                      - "We need to update the, we need to update the API endpoint" → "We need to update the API endpoint."
                      - "The file is in the docs, no hang on, the file is in the downloads folder" → "The file is in the downloads folder."
                    - Do not add content, restructure sentences, or change the paragraph layout.
                    - Output only the cleaned text. Nothing else.
                    """,
                icon: "cpu.fill",
                description: "Lightweight prompt optimised for on-device local models",
                isPredefined: true,
                useSystemInstructions: true
            )
        ]
    }
}
