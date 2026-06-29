import SwiftUI

/// First-run onboarding: what Siloquy is, the two ways to dictate, how to wire the
/// Action Button to a Shortcut, and a few usage tips. Shown once (an AppStorage flag),
/// and re-openable from the main toolbar.
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: finish)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .opacity(page == lastPage ? 0 : 1)
                    .disabled(page == lastPage)
            }

            TabView(selection: $page) {
                welcome.tag(0)
                ways.tag(1)
                setup.tag(2)
                tips.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < lastPage { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page < lastPage ? "Next" : "Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func finish() {
        hasSeenOnboarding = true
        dismiss()
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 76))
                .foregroundStyle(.tint)
            Text("Siloquy").font(.largeTitle.weight(.bold))
            Text("On-device dictation. Record your voice, clean it up, and copy the result — nothing ever leaves your phone.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding()
    }

    private var ways: some View {
        VStack(spacing: 28) {
            Text("Two ways to dictate").font(.title2.weight(.semibold))
            feature("mic.fill", "In the app",
                    "Tap Record, speak, and your cleaned-up text is ready to copy.")
            feature("button.programmable", "Action Button",
                    "Hands-free from any app — Siloquy records in the background and shows in the Dynamic Island.")
        }
        .padding(.horizontal, 28)
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set up the Action Button").font(.title2.weight(.semibold))
                Text("A one-time setup. In the Shortcuts app, make a shortcut with these two actions:")
                    .foregroundStyle(.secondary)
                shortcutDiagram
                step(1, "Open **Shortcuts** → **+** → add **Background Dictation** (under Siloquy).")
                step(2, "Add **Copy to Clipboard** right after — it auto-uses the dictation result.")
                step(3, "Name it **\u{201C}Siloquy Paste.\u{201D}**")
                step(4, "**Settings → Action Button → Shortcut → Siloquy Paste.**")
            }
            .padding(28)
        }
    }

    private var tips: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("Tips").font(.title2.weight(.semibold))
                feature("flame.fill", "Keep it warm",
                        "Open Siloquy now and then — the Action Button records instantly when the app's been used recently.")
                feature("stop.circle", "Stop from anywhere",
                        "Long-press the Dynamic Island and tap Stop, or press the Action Button again.")
                feature("doc.on.clipboard", "Paste anywhere",
                        "Your cleaned-up text lands on the clipboard — paste it into any app.")
            }
            .padding(28)
        }
    }

    // MARK: - Bits

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func step(_ n: Int, _ markdown: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(markdown).font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var shortcutDiagram: some View {
        VStack(spacing: 6) {
            diagramRow("1", "Background Dictation", "Siloquy")
            Image(systemName: "arrow.down").font(.caption).foregroundStyle(.secondary)
            diagramRow("2", "Copy to Clipboard", "Dictation result")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func diagramRow(_ n: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 10) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
