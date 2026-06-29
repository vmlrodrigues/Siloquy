import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = DictationViewModel()
    @ObservedObject private var launch = DictationLaunch.shared
    @ObservedObject private var bgDictation = BackgroundDictationController.shared
    @State private var lastHandledRequestID = 0
    @Query(sort: \DictationEntry.createdAt, order: .reverse) private var history: [DictationEntry]
    @AppStorage("historyRetention") private var retentionRaw = HistoryRetention.month.rawValue

    private let unavailableMessage = EnhancementService.unavailableMessage

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcriptArea
                Divider()
                controls
            }
            .navigationTitle("Siloquy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Image(systemName: "ladybug")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(entries: history)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
        // Slim "Recording…" screen shown while the background flow is active —
        // instead of the full app — so the Action Button launch is unobtrusive.
        .fullScreenCover(isPresented: Binding(get: { bgDictation.isRecording }, set: { _ in })) {
            RecordingOverlay()
        }
        // Warm path: a press while the app is already running.
        .onChange(of: launch.requestID) { _, newID in
            handleActionButton(newID)
        }
        // Cold path: a press that launched the app (the bump happened before this
        // view existed, so .onChange won't catch it).
        .task {
            handleActionButton(launch.requestID)
            HistoryMaintenance.prune(modelContext, retention: HistoryRetention(rawValue: retentionRaw) ?? .month)
        }
    }

    /// Toggle recording once per Action Button / Shortcut press.
    private func handleActionButton(_ id: Int) {
        guard id != lastHandledRequestID else { return }
        lastHandledRequestID = id
        Task { await vm.toggle(context: modelContext) }
    }

    // MARK: - Transcript / result area

    @ViewBuilder
    private var transcriptArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message = vm.statusMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if vm.isRecording || !vm.liveText.isEmpty {
                    sectionLabel("Listening")
                    Text(vm.liveText.isEmpty ? "Speak now…" : vm.liveText)
                        .foregroundStyle(vm.liveText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !vm.result.isEmpty {
                    sectionLabel(vm.enhancementEnabled ? "Cleaned up" : "Transcript")
                    Text(vm.result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !vm.isRecording && vm.liveText.isEmpty && vm.result.isEmpty {
                    emptyState
                }
            }
            .font(.title3)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Tap the button and start speaking.")
                .foregroundStyle(.secondary)
            if let unavailableMessage {
                Text(unavailableMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            Toggle(isOn: $vm.enhancementEnabled) {
                Label("Clean up with AI", systemImage: "sparkles")
            }
            .disabled(unavailableMessage != nil || vm.isRecording)

            recordButton

            if vm.isPreparingModel {
                Label("Preparing the speech model…", systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if vm.isEnhancing {
                Label("Cleaning up…", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }

    private var recordButton: some View {
        Button {
            Task { await vm.toggle(context: modelContext) }
        } label: {
            Label(vm.isRecording ? "Stop" : "Record",
                  systemImage: vm.isRecording ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(vm.isRecording ? .red : .accentColor)
    }
}

// MARK: - Recording overlay (the slim launch screen)

struct RecordingOverlay: View {
    @ObservedObject private var bgDictation = BackgroundDictationController.shared

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "waveform")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, isActive: true)
                Text("Recording…")
                    .font(.title2.weight(.semibold))
                Text("Switch back to your app — the Dynamic Island shows progress and a Stop button. Or stop here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                Button {
                    Task { await bgDictation.stopIfRecording(trigger: "OverlayButton") }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: 220, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @ObservedObject private var diag = DiagnosticLog.shared

    var body: some View {
        List {
            Section {
                if diag.lines.isEmpty {
                    Text("No background-dictation activity logged yet. Bind the Action Button to \"Background Dictate,\" press it, speak, press again — then come back here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(diag.lines.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Background dictation log (newest first)")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) { diag.clear() }
                    .disabled(diag.lines.isEmpty)
            }
        }
        .onAppear { diag.refresh() }
        .refreshable { diag.refresh() }
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("historyRetention") private var retentionRaw = HistoryRetention.month.rawValue
    @State private var copiedID: PersistentIdentifier?
    let entries: [DictationEntry]

    private var retention: HistoryRetention { HistoryRetention(rawValue: retentionRaw) ?? .month }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No dictations yet", systemImage: "clock",
                                       description: Text("Your past dictations will appear here."))
            }
            ForEach(entries) { entry in
                Button {
                    copy(entry)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.displayText)
                                .lineLimit(4)
                                .foregroundStyle(.primary)
                            Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if copiedID == entry.persistentModelID {
                            Label("Copied", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(entries[index]) }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Keep history for", selection: $retentionRaw) {
                        ForEach(HistoryRetention.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    if !entries.isEmpty {
                        Divider()
                        Button("Clear All History", systemImage: "trash", role: .destructive) {
                            for entry in entries { modelContext.delete(entry) }
                        }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .onChange(of: retentionRaw) { _, _ in
            HistoryMaintenance.prune(modelContext, retention: retention)
        }
    }

    private func copy(_ entry: DictationEntry) {
        UIPasteboard.general.string = entry.displayText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { copiedID = entry.persistentModelID }
        let id = entry.persistentModelID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedID == id { withAnimation { copiedID = nil } }
        }
    }
}
