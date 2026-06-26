import SwiftUI

struct OnboardingRecommendedSettingsView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager

    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OnboardingBackgroundView()

                VStack(spacing: 0) {
                    // Header — pinned at top
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 80, height: 80)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 34))
                                .foregroundColor(.accentColor)
                        }

                        Text("One last thing")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("These settings work well for most people.\nYou can always change them later in Settings.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .padding(.top, 48)
                    .padding(.bottom, 24)

                    // Settings list — scrolls if the window is too short to fit all rows
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(RecommendedSettings.items, id: \.title) { item in
                                settingRow(item)
                            }
                        }
                        .frame(width: min(geometry.size.width * 0.72, 480))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .opacity(opacity)

                    // Buttons — pinned at bottom
                    VStack(spacing: 14) {
                        Button {
                            RecommendedSettings.apply(
                                menuBarManager: menuBarManager,
                                recorderUIManager: recorderUIManager
                            )
                            hasCompletedOnboarding = true
                        } label: {
                            Text("Apply Recommended Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 260, height: 50)
                                .background(Color.accentColor)
                                .cornerRadius(25)
                        }
                        .buttonStyle(ScaleButtonStyle())

                        SkipButton(text: "Skip for now") {
                            hasCompletedOnboarding = true
                        }
                    }
                    .opacity(opacity)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1
                opacity = 1
            }
        }
    }

    private func settingRow(_ item: RecommendedSettings.Item) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: item.icon)
                    .font(.system(size: 15))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.25))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
