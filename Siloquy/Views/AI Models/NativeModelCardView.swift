import SwiftUI
import AppKit

// MARK: - Native Apple Model Card View
struct NativeAppleModelCardView: View {
    let model: NativeAppleModel
    let isCurrent: Bool
    var setDefaultAction: () -> Void

    @ObservedObject private var languages = DictationLanguageManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Main Content
            VStack(alignment: .leading, spacing: 6) {
                headerSection
                metadataSection
                descriptionSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Action Controls
            actionSection
        }
        .padding(16)
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            Spacer()
        }
    }
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Native Apple
            Label("Native Apple", systemImage: "apple.logo")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // On-Device
            Label("On-Device", systemImage: "checkmark.shield")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Apple installs a separate asset per locale, so listing this card under
            // "Downloaded" says only that the framework is present — which read as a
            // promise that every language was ready when most were not.
            if let readiness = downloadReadiness {
                Label(readiness.text, systemImage: readiness.complete ? "checkmark.circle" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(readiness.complete ? Color(.secondaryLabelColor) : .orange)
                    .lineLimit(1)
                    .help("Each language downloads its own model. Download them per language under Dictation Languages above.")
            }
        }
        .lineLimit(1)
    }

    /// How many of *your* languages are actually ready.
    ///
    /// A list of installed locales would be both too long and beside the point — macOS
    /// carries English variants nobody asked for. What matters is whether the languages
    /// you set up will work, so the card counts those and says so where the card would
    /// otherwise imply, by sitting under "Downloaded", that all of them do.
    private var downloadReadiness: (text: String, complete: Bool)? {
        let mine = languages.enabled.filter { languages.model(for: $0)?.provider == .nativeApple }
        guard !mine.isEmpty else { return nil }

        let ready = mine.filter { languages.installedAppleLocales.contains($0.id) }.count
        return ("\(ready)/\(mine.count) languages ready", ready == mine.count)
    }
    
    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private var actionSection: some View {
        HStack(spacing: 8) {
            ModelLanguageAssignment(model: model)
        }
    }
} 
