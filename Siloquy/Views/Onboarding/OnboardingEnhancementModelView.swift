import SwiftUI

/// Second model-download step in onboarding: the local AI enhancement model (Gemma).
/// Shown after the Parakeet transcription model. Downloading it and finishing here sets
/// `gemmaLocal` as the enhancement provider so grammar cleanup works fully offline.
struct OnboardingEnhancementModelView: View {
    @Binding var hasCompletedOnboarding: Bool
    @ObservedObject var gemmaService: GemmaService
    @EnvironmentObject private var aiService: AIService

    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var isModelSet = false

    private let model = GemmaService.catalog.first { $0.id == "gemma4-e2b" }!

    private var downloadState: DownloadState {
        gemmaService.downloadStates[model.id] ?? .notDownloaded
    }

    private var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        return false
    }

    private var downloadProgress: Double {
        if case .downloading(let value) = downloadState { return value }
        return 0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OnboardingBackgroundView()

                VStack(spacing: 40) {
                    VStack(spacing: 30) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 100, height: 100)

                            Image(systemName: isModelSet ? "checkmark.seal.fill" : "sparkles")
                                .font(.system(size: isModelSet ? 50 : 40))
                                .foregroundColor(.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                        .scaleEffect(scale)
                        .opacity(opacity)

                        VStack(spacing: 12) {
                            Text("Download AI Enhancement Model")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Gemma runs fully on your Mac to clean up grammar and disfluencies — no API key, no internet.")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .scaleEffect(scale)
                        .opacity(opacity)
                    }

                    VStack(alignment: .center, spacing: 12) {
                        Text(model.displayName)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(model.detail)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        if isDownloading {
                            VStack(spacing: 8) {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(.linear)
                                    .tint(Color.accentColor)
                                Text("Downloading… \(Int(downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.top, 4)
                            .transition(.opacity)
                        }

                        if case .error(let message) = downloadState {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(24)
                    .frame(width: min(geometry.size.width * 0.6, 400))
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .scaleEffect(scale)
                    .opacity(opacity)

                    VStack(spacing: 16) {
                        Button(action: handleAction) {
                            Text(buttonTitle)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.accentColor)
                                .cornerRadius(25)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isDownloading)

                        if !isModelSet {
                            SkipButton(text: "Skip for now") {
                                hasCompletedOnboarding = true
                            }
                        }
                    }
                    .opacity(opacity)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: min(geometry.size.width * 0.8, 600))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1
                opacity = 1
            }
            isModelSet = gemmaService.isDownloaded(model)
        }
        .onChange(of: downloadState) { _, newValue in
            if newValue == .downloaded {
                aiService.selectedProvider = .gemmaLocal
                withAnimation { isModelSet = true }
            }
        }
    }

    private var buttonTitle: String {
        if isModelSet { return "Finish" }
        if isDownloading { return "Downloading…" }
        return "Download Model"
    }

    private func handleAction() {
        if isModelSet {
            aiService.selectedProvider = .gemmaLocal
            hasCompletedOnboarding = true
            return
        }

        if gemmaService.isDownloaded(model) {
            aiService.selectedProvider = .gemmaLocal
            withAnimation { isModelSet = true }
            return
        }

        gemmaService.startDownload(for: model)
    }
}
