import SwiftUI

struct OnboardingModelDownloadView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var aiService: AIService
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var isDownloading = false
    @State private var isModelSet = false
    @State private var showEnhancementModel = false

    private let parakeetModel = TranscriptionModelRegistry.models.first { $0.name == "parakeet-tdt-0.6b-v2" } as! FluidAudioModel

    var body: some View {
        ZStack {
        GeometryReader { geometry in
            ZStack {
                OnboardingBackgroundView()

                VStack(spacing: 40) {
                    // Icon and title
                    VStack(spacing: 30) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 100, height: 100)

                            if isModelSet {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "waveform")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .scaleEffect(scale)
                        .opacity(opacity)

                        VStack(spacing: 12) {
                            Text("Download Transcription Model")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Parakeet runs entirely on your device — no internet needed after download.")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .scaleEffect(scale)
                        .opacity(opacity)
                    }

                    // Model card
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .center, spacing: 8) {
                            Text(parakeetModel.displayName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(parakeetModel.size) · \(parakeetModel.language)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)

                        Divider()
                            .background(Color.white.opacity(0.1))

                        HStack(spacing: 20) {
                            performanceIndicator(label: "Speed", value: parakeetModel.speed)
                            performanceIndicator(label: "Accuracy", value: parakeetModel.accuracy)
                            ramUsageLabel(gb: parakeetModel.ramUsage)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        if isDownloading {
                            let progress = fluidAudioModelManager.downloadStatus(for: parakeetModel)?.fractionCompleted ?? 0
                            let message = fluidAudioModelManager.downloadStatus(for: parakeetModel)?.message ?? "Downloading…"
                            VStack(spacing: 8) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(Color.accentColor)
                                HStack(spacing: 6) {
                                    // Always-animating so it never looks stuck while one large
                                    // model file downloads and the bar can't advance (#27).
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .transition(.opacity)
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

                    // Action buttons
                    VStack(spacing: 16) {
                        Button(action: handleAction) {
                            Text(getButtonTitle())
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
                                showEnhancementModel = true
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
            animateIn()
            checkModelStatus()
        }

            if showEnhancementModel {
                OnboardingEnhancementModelView(
                    hasCompletedOnboarding: $hasCompletedOnboarding,
                    gemmaService: aiService.gemmaService
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }

    private func checkModelStatus() {
        isModelSet = fluidAudioModelManager.isFluidAudioModelDownloaded(parakeetModel)
    }

    private func handleAction() {
        if isModelSet {
            showEnhancementModel = true
            return
        }

        if fluidAudioModelManager.isFluidAudioModelDownloaded(parakeetModel) {
            if let modelToSet = transcriptionModelManager.allAvailableModels.first(where: { $0.name == parakeetModel.name }) {
                transcriptionModelManager.setDefaultTranscriptionModel(modelToSet)
            }
            withAnimation { isModelSet = true }
            return
        }

        withAnimation { isDownloading = true }
        Task {
            await fluidAudioModelManager.downloadFluidAudioModel(parakeetModel)
            if let modelToSet = transcriptionModelManager.allAvailableModels.first(where: { $0.name == parakeetModel.name }) {
                transcriptionModelManager.setDefaultTranscriptionModel(modelToSet)
            }
            withAnimation {
                isModelSet = true
                isDownloading = false
            }
        }
    }

    private func getButtonTitle() -> String {
        if isModelSet { return "Continue" }
        if isDownloading { return "Downloading…" }
        if fluidAudioModelManager.isFluidAudioModelDownloaded(parakeetModel) { return "Set as Default" }
        return "Download Model"
    }

    private func performanceIndicator(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(Double(index) / 5.0 <= value ? Color.accentColor : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    private func ramUsageLabel(gb: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Text(String(format: "%.1f GB", gb))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
