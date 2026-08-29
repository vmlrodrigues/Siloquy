import SwiftUI

/// The "use this model" control on a model card.
///
/// Replaces a global "Set as Default". With a model per dictation language, assigning
/// one is always assigning it *to a language* — Parakeet is the default for English and
/// meaningless for Portuguese — so the button names the language it will apply to
/// rather than implying the choice is global.
struct ModelLanguageAssignment: View {
    let model: any TranscriptionModel

    @ObservedObject private var languages = DictationLanguageManager.shared

    var body: some View {
        let language = languages.current

        if !language.isSupported(by: model) {
            // Offering the button would be a trap: assigning it would either fail or
            // silently fall back to a language the user did not ask for.
            Text("No \(language.nativeName)")
                .font(.system(size: 12))
                .foregroundColor(Color(.tertiaryLabelColor))
                .help("\(model.displayName) cannot transcribe \(language.englishName).")
        } else if languages.model(for: language)?.name == model.name {
            Text("Used for \(language.nativeName)")
                .font(.system(size: 12))
                .foregroundColor(Color(.secondaryLabelColor))
        } else {
            Button {
                languages.setModel(model, for: language)
            } label: {
                Text("Use for \(language.nativeName)")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Make \(model.displayName) the model used when you dictate in \(language.englishName).")
        }
    }
}
