import SwiftUI

struct LicenseManagementView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()
    @Environment(\.colorScheme) private var colorScheme
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection

                VStack(spacing: 32) {
                    attributionSection
                }
                .padding(32)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var heroSection: some View {
        VStack(spacing: 24) {
            AppIconView()

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("Siloquy")
                            .font(.system(size: 32, weight: .bold))

                        Text("v\(appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                }

                Text("On-device speech-to-text with AI enhancement")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = URL(string: "https://github.com/vmlrodrigues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("by Victor Rodrigues")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 60)
    }

    private var licenseContent: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("VoiceInk Pro License")
                    .font(.headline)

                Text("If you own a VoiceInk Pro license you can activate it here. Siloquy validates licenses against the original VoiceInk licensing server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    TextField("Enter your license key", text: $licenseViewModel.licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .textCase(.uppercase)

                    Button(action: {
                        Task { await licenseViewModel.validateLicense() }
                    }) {
                        if licenseViewModel.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Activate")
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseViewModel.isValidating)
                }

                if let message = licenseViewModel.validationMessage {
                    Text(message)
                        .foregroundColor(licenseViewModel.validationSuccess ? .green : .red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }

    private var activatedContent: some View {
        VStack(spacing: 32) {
            VStack(spacing: 24) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    Text("License Active")
                        .font(.headline)
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green))
                        .foregroundStyle(.white)
                }

                Divider()

                if licenseViewModel.activationsLimit > 0 {
                    Text("This license can be activated on up to \(licenseViewModel.activationsLimit) devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You can use this license on all your personal devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)

            VStack(alignment: .leading, spacing: 16) {
                Text("License Management")
                    .font(.headline)

                Button(role: .destructive, action: {
                    licenseViewModel.removeLicense()
                }) {
                    Label("Deactivate License", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }

    private var attributionSection: some View {
        VStack(spacing: 16) {
            Divider()

            VStack(spacing: 12) {
                Text("Credits")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 32) {
                    VStack(spacing: 4) {
                        Text("This fork")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        Button {
                            if let url = URL(string: "https://github.com/vmlrodrigues/Siloquy") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Victor Rodrigues")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().frame(height: 36)

                    VStack(spacing: 4) {
                        Text("Original VoiceInk")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        Button {
                            if let url = URL(string: "https://github.com/Beingpax/VoiceInk") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Prakash Joshi Pax")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    EmailSupport.openSupportEmail()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                        Text("Contact")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }

    private func featureItem(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
