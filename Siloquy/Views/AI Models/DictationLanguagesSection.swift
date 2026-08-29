import SwiftUI

/// The languages you dictate *in*, each with its own shortcut.
///
/// Lives beside the model list rather than in Settings because choosing a dictation
/// language *is* choosing a transcription model — Parakeet cannot do Portuguese, so
/// the two decisions are one decision, and splitting them across two screens invites
/// the incoherent pairing this section exists to prevent.
struct DictationLanguagesSection: View {
    @ObservedObject private var manager = DictationLanguageManager.shared
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    /// Removing also discards that language's shortcut, which is not obvious from a
    /// single small button and cannot be undone.
    @State private var languageToRemove: DictationLanguage?
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictation Languages")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(manager.enabled.enumerated()), id: \.element.id) { index, language in
                    if index > 0 {
                        Divider()
                    }
                    row(for: language)
                }
            }

            if !manager.addable.isEmpty {
                Menu {
                    ForEach(manager.addable) { language in
                        Button {
                            manager.enable(language)
                        } label: {
                            // Endonym first — a speaker scans for their own word for
                            // the language, not ours for it.
                            Text("\(language.flag)  \(language.nativeName)  ·  \(language.englishName)")
                        }
                    }
                } label: {
                    Label("Add a language…", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text(footerText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        // A confirmation dialog rather than an alert: `ModelManagementView` already owns
        // an `.alert` on the enclosing ScrollView, and only one alert presents per
        // hierarchy — a nested one silently never appears.
        .confirmationDialog(
            languageToRemove.map { "Remove \($0.nativeName)?" } ?? "",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible,
            presenting: languageToRemove
        ) { language in
            Button("Remove", role: .destructive) {
                manager.disable(language)
                languageToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                languageToRemove = nil
            }
        } message: { _ in
            Text("Its shortcut will be cleared. The downloaded language model stays on your Mac, so adding it back later needs no download.")
        }
    }

    private func row(for language: DictationLanguage) -> some View {
        HStack(spacing: 9) {
            Text(language.flag)
            VStack(alignment: .leading, spacing: 1) {
                Text(language.nativeName)
                Text(engineDescription(for: language))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            // Apple ships a separate asset per locale and none are present until asked
            // for. Without this the first dictation in a new language fails *after* you
            // have finished speaking, which is the one moment an error is no use at all.
            NativeAppleLanguageAssetControl(
                localeIdentifier: language.id,
                isVisible: language.usesAppleSpeech
            )

            // A shortcut is only meaningful once there is somewhere to switch to, so it
            // appears with the second language.
            if manager.enabled.count > 1 {
                ShortcutRecorder(action: .dictationLanguage(language.id)) {
                    recordingShortcutManager.updateShortcutStatus()
                }
                .controlSize(.small)
            }

            if language.isRemovable {
                Button {
                    languageToRemove = language
                    isConfirmingRemoval = true
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(language.nativeName)")
            }
        }
        .padding(.vertical, 8)
    }

    /// Names the engine and locale so it is clear that picking a language changes the
    /// transcriber too, rather than being a hint passed to the same one.
    private func engineDescription(for language: DictationLanguage) -> String {
        let engine = language.usesAppleSpeech ? "Apple SpeechAnalyzer" : "Parakeet v2"
        return "\(engine) · \(language.id)"
    }

    private var footerText: String {
        guard manager.enabled.count > 1 else {
            return "Add a language to dictate in it. Each one gets its own shortcut, and switching also switches the transcription model above."
        }
        return "Download a language before its first use, then press its shortcut before you start dictating — the transcriber is already running once recording begins, so it can't be changed part-way through."
    }
}
