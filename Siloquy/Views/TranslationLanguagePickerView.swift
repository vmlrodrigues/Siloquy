import SwiftUI

/// Add-translation panel (#25): pick one or more target languages; each becomes a
/// deletable prompt tile that takes the next free ⌘ shortcut slot. Languages already
/// added are hidden so they can't be duplicated.
struct TranslationLanguagePickerView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    var onDismiss: (() -> Void)?

    @State private var selected: Set<String> = []
    @State private var search: String = ""

    private var available: [TranslationLanguage] {
        let existing = Set(enhancementService.customPrompts.compactMap { $0.targetLanguage })
        return TranslationLanguage.all
            .filter { !existing.contains($0.id) }
            .filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if TranslationLanguage.all.allSatisfy({ id in enhancementService.customPrompts.contains { $0.targetLanguage == id.id } }) {
                emptyState
            } else {
                searchField
                languageList
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Translation")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Each language becomes its own prompt tile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search languages", text: $search)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var languageList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(available) { lang in
                    Button {
                        if selected.contains(lang.id) { selected.remove(lang.id) }
                        else { selected.insert(lang.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(lang.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected.contains(lang.id) ? .accentColor : .secondary)
                            Text(lang.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected.contains(lang.id) ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selected.contains(lang.id) ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Best on Gemma 4 E4B, which handles these well — including European and Brazilian Portuguese.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let langs = selected.compactMap { TranslationLanguage.language(forID: $0) }
                enhancementService.addTranslationPrompts(langs)
                onDismiss?()
            } label: {
                Text(selected.isEmpty ? "Add" : "Add \(selected.count)")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("All languages added")
                .font(.subheadline)
            Text("You've added every offered language. Remove one by right-clicking its tile.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
