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
                    Text("Enhancement Prompts")
                    Spacer()
                    Menu {
                        Button {
                            openPromptPanel()
                            withAnimation(.smooth(duration: 0.3)) {
                                isEditingPrompt = true
                            }
                        } label: {
                            Label("New prompt", systemImage: "doc.badge.plus")
                        }
                        Button {
                            openPromptPanel()
                            withAnimation(.smooth(duration: 0.3)) {
                                isAddingTranslation = true
                            }
                        } label: {
                            Label("Add translation…", systemImage: "globe")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
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

    @State private var draggingItem: CustomPrompt?

    /// The ⌘-number shortcut for a tile at this position — ⌘1…⌘9 then ⌘0 for the
    /// tenth, nothing beyond. Mirrors MiniRecorderShortcutManager's positional mapping.
    static func shortcutLabel(for index: Int) -> String? {
        if index < 9 { return "⌘\(index + 1)" }
        if index == 9 { return "⌘0" }
        return nil
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
                    ForEach(Array(enhancementService.customPrompts.enumerated()), id: \.element.id) { index, prompt in
                        prompt.promptIcon(
                            isSelected: selectedPromptId == prompt.id,
                            shortcutNumber: Self.shortcutLabel(for: index),
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onPromptSelected(prompt)
                                }
                            },
                            onEdit: onEditPrompt,
                            onDelete: onDeletePrompt
                        )
                        .opacity(draggingItem?.id == prompt.id ? 0.3 : 1.0)
                        .scaleEffect(draggingItem?.id == prompt.id ? 1.05 : 1.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.15), value: draggingItem?.id == prompt.id)
                        .onDrag {
                            draggingItem = prompt
                            return NSItemProvider(object: prompt.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PromptDropDelegate(
                                item: prompt,
                                prompts: $enhancementService.customPrompts,
                                draggingItem: $draggingItem
                            )
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                HStack {
                    Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text("Double-click to edit • Right-click for more options")
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
private struct PromptDropDelegate: DropDelegate {
    let item: CustomPrompt
    @Binding var prompts: [CustomPrompt]
    @Binding var draggingItem: CustomPrompt?

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem != item else { return }
        guard let fromIndex = prompts.firstIndex(of: draggingItem),
              let toIndex = prompts.firstIndex(of: item) else { return }

        if prompts[toIndex].id != draggingItem.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                let from = fromIndex
                let to = toIndex
                prompts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}
