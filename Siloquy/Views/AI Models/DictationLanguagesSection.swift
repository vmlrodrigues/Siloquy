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
    @State private var hoveredLanguage: DictationLanguage?
    @State private var pushedCursor = false

    /// Wide enough for the unbound "Record" button, which is the widest state the
    /// recorder takes.
    private let shortcutColumnWidth: CGFloat = 112

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
            // Careful not to over-promise: removing releases the locale's reservation,
            // which is precisely what makes macOS willing to reclaim the model. It
            // usually survives, but it is not ours to keep or to delete.
            Text("Its shortcut will be cleared. The speech model belongs to macOS, which reclaims it when it needs the space — so re-adding this language often needs no download, and nothing can delete it on demand.")
        }
    }

    private func row(for language: DictationLanguage) -> some View {
        // One resolution per row. Asking the manager for the model, the missing model
        // and the readiness separately re-walked every registry model each time, and
        // each walk asked the Keychain about every cloud provider.
        let state = manager.state(of: language)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                // Clicking the language switches to it. A shortcut is the fast path once
                // you know it, but it cannot be the only path: nothing on screen would
                // otherwise let you change language, and a shortcut you have not bound
                // yet leaves you stuck.
                Button {
                    manager.select(language)
                } label: {
                    HStack(spacing: 9) {
                        // A filled dot for the active language, hollow for the rest —
                        // the row is a choice, and without a mark for the unchosen ones
                        // there is nothing to suggest they can be picked.
                        Image(systemName: language == manager.current
                              ? "largecircle.fill.circle"
                              : "circle")
                            .foregroundColor(language == manager.current ? .accentColor : .secondary)
                            .font(.system(size: 12))

                        Text(language.flag)
                        Text(language.nativeName)
                            .fontWeight(language == manager.current ? .semibold : .regular)
                            .foregroundColor(.primary)

                        if language == manager.current {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredLanguage == language && language != manager.current
                                  ? Color.primary.opacity(0.08)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    hoveredLanguage = inside ? language : (hoveredLanguage == language ? nil : hoveredLanguage)
                    // Track what we pushed: the push is conditional but the pop was not,
                    // so hovering the active row popped a cursor this view never pushed
                    // and unbalanced AppKit's stack.
                    // The pointer is the other half of the signal: a hand says "this
                    // does something" before the row has been hovered long enough to
                    // notice the background.
                    if inside, language != manager.current, !pushedCursor {
                        NSCursor.pointingHand.push()
                        pushedCursor = true
                    } else if !inside, pushedCursor {
                        NSCursor.pop()
                        pushedCursor = false
                    }
                }
                .help(language == manager.current
                      ? "Already dictating in \(language.nativeName)"
                      : "Click to dictate in \(language.nativeName)")

                Spacer(minLength: 12)

                // Fixed columns so every row's controls line up on the right. The
                // recorder is wider unbound ("Record") than bound ("⌥⌘E"), and English
                // has no remove button, so without reserved widths each row's controls
                // sat at a different offset.
                if manager.enabled.count > 1 {
                    ShortcutRecorder(action: .dictationLanguage(language.id)) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                    .frame(width: shortcutColumnWidth, alignment: .trailing)
                }

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
                // English cannot be removed, but its slot is still reserved so the
                // shortcut column above it does not shift.
                .opacity(language.isRemovable ? 1 : 0)
                .disabled(!language.isRemovable)
                .accessibilityHidden(!language.isRemovable)
            }

            HStack(spacing: 8) {
                modelPicker(for: language, state: state)
                readiness(for: language, state: state)
            }
            .padding(.leading, 46)
        }
        .padding(.vertical, 6)
    }

    /// Says plainly when a language cannot be used yet.
    ///
    /// Apple ships a separate asset per locale, so "Apple Speech is downloaded" is not a
    /// fact about a language — German can be picked while its asset is absent. A bare
    /// download arrow read as an optional extra rather than a blocker, and the failure
    /// only surfaced after a whole dictation had been spoken.
    @ViewBuilder
    private func readiness(for language: DictationLanguage, state: DictationLanguageManager.LanguageState) -> some View {
        if manager.isDownloading(language) {
            HStack(spacing: 5) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Downloading \(language.englishName)…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if let missing = state.missing {
            // The transcriber itself is absent, not just this language's slice of it.
            // Downloading it belongs in the model list below, where its size and
            // progress are shown, so this points there rather than duplicating it.
            Label("Needs \(missing.displayName)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
                .help("\(missing.displayName) is the only model here that transcribes \(language.englishName). Download it under Downloaded or Local below, and this language becomes usable.")
        } else if !state.isReady {
            HStack(spacing: 6) {
                Label("Not downloaded", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Button("Download") {
                    Task { await manager.download(language) }
                }
                .controlSize(.small)
                .help("Download the \(language.englishName) speech model. Until then this language can't be used.")
            }
        }
    }

    @ViewBuilder
    private func modelPicker(for language: DictationLanguage, state: DictationLanguageManager.LanguageState) -> some View {
        let candidates = state.candidates
        let usable = Set(state.usable.map(\.name))
        let selected = state.selected

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
                            Text(usable.contains(model.name)
                                 ? model.displayName
                                 : "\(model.displayName) — not downloaded")
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
