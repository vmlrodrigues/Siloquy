import SwiftUI

/// The languages you dictate in, each with its own model and shortcut.
///
/// The language is the organising unit, not the model. A single global "default model"
/// is only ever true for whichever language is active — Parakeet cannot transcribe
/// Portuguese — so the model is shown where it applies, on the language that uses it.
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
                        Divider().padding(.vertical, 4)
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
        let selected = manager.model(for: language)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(language.flag)
                Text(language.nativeName)
                    .fontWeight(language == manager.current ? .semibold : .regular)

                if language == manager.current {
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundColor(.accentColor)
                }

                Spacer(minLength: 12)

                // A shortcut is only meaningful once there is somewhere to switch to,
                // so it appears with the second language.
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

            HStack(spacing: 8) {
                modelPicker(for: language, selected: selected)

                // Apple ships a separate asset per locale and none are present until
                // asked for. Without this the first dictation in a new language fails
                // *after* you have finished speaking, which is the one moment an error
                // is no use at all.
                NativeAppleLanguageAssetControl(
                    localeIdentifier: language.id,
                    isVisible: selected?.provider == .nativeApple
                )
            }
            .padding(.leading, 26)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func modelPicker(for language: DictationLanguage, selected: (any TranscriptionModel)?) -> some View {
        let candidates = manager.usableModels(for: language)

        if candidates.isEmpty {
            Label("No model on this Mac can transcribe \(language.englishName)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        } else {
            Menu {
                ForEach(candidates, id: \.name) { model in
                    Button {
                        manager.setModel(model, for: language)
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if model.name == selected?.name {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selected?.displayName ?? "Choose a model")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
                .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Only worth flagging when the model collapses two languages you can
            // actually pick between — Whisper has no pt-PT, only pt, so choosing it for
            // Português gets you the same transcriber as Português (Brasil).
            if let selected,
               let code = language.languageCode(for: selected),
               code != language.id,
               !language.variantSiblings.isEmpty {
                Label("uses \(code)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help("\(selected.displayName) has no separate \(language.englishName) model — it transcribes all \(code) variants the same way, including \(language.variantSiblings.map(\.nativeName).joined(separator: ", ")).")
            }
        }
    }

    private var footerText: String {
        guard manager.enabled.count > 1 else {
            return "Add a language to dictate in it. Each language gets its own model and its own shortcut, so switching language switches the transcriber too."
        }
        return "Download a language before its first use, then press its shortcut before you start dictating — the transcriber is already running once recording begins, so it can't be changed part-way through."
    }
}
