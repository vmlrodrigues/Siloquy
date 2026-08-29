import SwiftUI

/// Settings for the languages you dictate *in*.
///
/// Only appears once you add a second language. On a single-language setup there is
/// nothing to choose between, and a section explaining a choice you don't have is
/// noise — so the entry point is a single "Add a language…" row until it earns more.
struct DictationLanguagesSection: View {
    @ObservedObject private var manager = DictationLanguageManager.shared
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager

    var body: some View {
        Section {
            ForEach(manager.enabled) { language in
                LabeledContent {
                    HStack(spacing: 10) {
                        // Apple ships a separate asset per locale and none are present
                        // until asked for. Without this the first dictation in a new
                        // language fails *after* you have finished speaking, which is
                        // the one moment an error is no use at all.
                        NativeAppleLanguageAssetControl(
                            localeIdentifier: language.id,
                            isVisible: language.usesAppleSpeech
                        )
                        // A shortcut is only meaningful once there is somewhere to
                        // switch to, so it appears with the second language.
                        if manager.enabled.count > 1 {
                            ShortcutRecorder(action: .dictationLanguage(language.id)) {
                                recordingShortcutManager.updateShortcutStatus()
                            }
                            .controlSize(.small)
                        }
                        if language.isRemovable {
                            Button {
                                manager.disable(language)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(language.nativeName)")
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Text(language.flag)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(language.nativeName)
                            Text(engineDescription(for: language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
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
        } header: {
            Text("Dictation Languages")
        } footer: {
            Text(footerText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Names the engine and locale so it is clear that picking a language changes the
    /// transcriber too, rather than being a hint passed to the same one.
    private func engineDescription(for language: DictationLanguage) -> String {
        let engine = language.usesAppleSpeech ? "Apple SpeechAnalyzer" : "Parakeet v2"
        return "\(engine) · \(language.id)"
    }

    private var footerText: String {
        guard manager.enabled.count > 1 else {
            return "Add a language to dictate in it. Each one gets its own shortcut, and switching also switches the transcription engine."
        }
        return "Download a language before its first use, then press its shortcut before you start dictating — the transcriber is already running once recording begins, so it can't be changed part-way through."
    }
}
