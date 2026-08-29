import SwiftUI
import UniformTypeIdentifiers

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isEditingPrompt = false
    @State private var isShowingSettings = false
    @State private var isAddingTranslation = false
    @State private var selectedPromptForEdit: CustomPrompt?
    @State private var panelID = UUID()

    private let panelWidth: CGFloat = 400

    private enum PanelType {
        case promptEditor
        case settings
        case translationPicker
    }

    private var activePanel: PanelType? {
        if isShowingSettings { return .settings }
        if isAddingTranslation { return .translationPicker }
        if isEditingPrompt || selectedPromptForEdit != nil { return .promptEditor }
        return nil
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }

    private func openPromptPanel() {
        isShowingSettings = false
        panelID = UUID()
    }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.3)) {
            isEditingPrompt = false
            selectedPromptForEdit = nil
            isShowingSettings = false
            isAddingTranslation = false
        }
    }

    /// The enhancement default is a single choice: Enhanced (enhancement stays on until you
    /// turn it off) or Raw (each dictation starts off; opt in per dictation). The picker is
    /// false = Enhanced, true = Raw, mapped onto the live state plus the per-dictation reset
    /// flag — so the control can never contradict itself the way two separate toggles did.
    private var enhancementDefaultBinding: Binding<Bool> {
        Binding(
            get: { enhancementService.resetEnhancementPerDictation },
            set: { startsRaw in
                enhancementService.resetEnhancementPerDictation = startsRaw
                enhancementService.isEnhancementEnabled = !startsRaw
            }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("New dictations start")
                        InfoTip(
                            "Enhanced: every dictation is cleaned up by AI. Raw: dictations stay exactly as spoken. Either way, the enhancement shortcut (⌥) flips just the current dictation, and Power Mode or a trigger word can still turn it on."
                        )
                        Spacer()
                    }
                    Picker("New dictations start", selection: enhancementDefaultBinding) {
                        Text("Enhanced").tag(false)
                        Text("Raw").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            } header: {
                HStack {
                    Text("General")
                    Spacer()
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = false
                            selectedPromptForEdit = nil
                            isShowingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Enhancement settings")
                }
            }

            APIKeyManagementView()

            Section {
                ReorderablePromptGrid(
                    selectedPromptId: enhancementService.selectedPromptId,
                    onPromptSelected: { prompt in
                        enhancementService.setActivePrompt(prompt)
                    },
                    onEditPrompt: { prompt in
                        openPromptPanel()
                        withAnimation(.smooth(duration: 0.3)) {
                            selectedPromptForEdit = prompt
                        }
                    },
                    onDeletePrompt: { prompt in
                        enhancementService.deletePrompt(prompt)
                    }
                )
                .padding(.vertical, 8)
            } header: {
                HStack {
                    Text("Enhancement & Translation Prompts")
                    Spacer()
                    // "Add translation…" is gone: destinations come from your dictation
                    // languages now, so adding one there adds its tile here.
                    Button {
                        openPromptPanel()
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New prompt")
                    .help("Add a prompt or translation")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .slidingPanel(isPresented: .init(
            get: { isPanelOpen },
            set: { newValue in
                if !newValue { closePanel() }
            }
        ), width: panelWidth) {
            Group {
                switch activePanel {
                case .settings:
                    EnhancementSettingsPanel(onDismiss: closePanel)
                case .translationPicker:
                    TranslationLanguagePickerView(onDismiss: closePanel)
                        .id(panelID)
                case .promptEditor:
                    Group {
                        if let prompt = selectedPromptForEdit {
                            PromptEditorView(mode: .edit(prompt)) {
                                closePanel()
                            }
                        } else if isEditingPrompt {
                            PromptEditorView(mode: .add) {
                                closePanel()
                            }
                        }
                    }
                    .id(panelID)
                case nil:
                    EmptyView()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Reorderable Grid
private struct ReorderablePromptGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService

    let selectedPromptId: UUID?
    let onPromptSelected: (CustomPrompt) -> Void
    let onEditPrompt: ((CustomPrompt) -> Void)?
    let onDeletePrompt: ((CustomPrompt) -> Void)?


    /// The ⌘-number shortcut for a tile at this position — ⌘1…⌘9 then ⌘0 for the
    /// tenth, nothing beyond. Mirrors MiniRecorderShortcutManager's positional mapping.
    static func shortcutLabel(for index: Int) -> String? {
        if index < 9 { return "⌘\(index + 1)" }
        if index == 9 { return "⌘0" }
        return nil
    }

    /// The placeholder for the dictation language you are currently speaking.
    @ViewBuilder
    private func reservedSlot(number: String?) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Text(DictationLanguageManager.shared.current.flag)
                        .font(.system(size: 20))
                        .opacity(0.45)
                )
                .overlay(alignment: .topLeading) {
                    if let number {
                        Text(number)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                            .offset(x: -5, y: -5)
                    }
                }

            Text("Speaking \(DictationLanguageManager.shared.current.tileName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: 70)
        }
        .opacity(0.55)
        .help("\(DictationLanguageManager.shared.current.nativeName) keeps this key so the others never move. There is nothing to translate into the language you are already speaking.")
    }

    /// Authored prompts belonging to a language other than the one in use.
    private var outOfScopePrompts: [CustomPrompt] {
        let offered = Set(enhancementService.allPrompts.map(\.id))
        return enhancementService.customPrompts.filter { !offered.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enhancementService.customPrompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    // Driven by the slot list, so what you see is the ⌘ order: no
                    // separate pass for generated tiles, and no way for the drawn order
                    // to disagree with the numbering.
                    ForEach(Array(enhancementService.promptSlots.enumerated()), id: \.offset) { slotIndex, slot in
                        if slot == nil {
                            // The slot your own language holds. Drawn rather than
                            // omitted, because a missing tile just reads as a missing
                            // ⌘3 — this says the key is spoken for, and by what. It is
                            // inert: there is nothing to translate into the language you
                            // are already speaking.
                            reservedSlot(number: Self.shortcutLabel(for: slotIndex))
                        } else if let prompt = slot {
                            prompt.promptIcon(
                                isSelected: selectedPromptId == prompt.id,
                                shortcutNumber: Self.shortcutLabel(for: slotIndex),
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        onPromptSelected(prompt)
                                    }
                                },
                                // Generated translation tiles come from the language
                                // list, so there is nothing to edit or delete on them.
                                onEdit: prompt.isTranslation ? nil : onEditPrompt,
                                onDelete: prompt.isTranslation ? nil : onDeletePrompt
                            )
                        }
                    }

                    // Prompts scoped to another language keep their place in the grid so
                    // they can still be edited, but have no ⌘ number while out of scope.
                    ForEach(outOfScopePrompts, id: \.id) { prompt in
                        prompt.promptIcon(
                            isSelected: false,
                            onTap: {},
                            onEdit: onEditPrompt,
                            onDelete: onDeletePrompt
                        )
                        .opacity(0.4)
                        .overlay(alignment: .topLeading) {
                            if let scope = prompt.dictationLanguage,
                               let language = DictationLanguage.named(scope) {
                                Text(language.flag)
                                    .font(.system(size: 11))
                                    .padding(3)
                                    .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                                    .offset(x: -4, y: -4)
                                    .help("Only offered when dictating in \(language.nativeName)")
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                HStack {
                    Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text(DictationLanguageManager.shared.enabled.count > 1
                         ? "⌘1 is always the clean-up prompt • Double-click to edit • Translation tiles come from your dictation languages and keep a fixed key each"
                         : "Double-click to edit • Right-click for more options")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Drop Delegate
