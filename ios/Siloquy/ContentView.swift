import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = DictationViewModel()
    @ObservedObject private var launch = DictationLaunch.shared
    @State private var lastHandledRequestID = 0
    @Query(sort: \DictationEntry.createdAt, order: .reverse) private var history: [DictationEntry]

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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(entries: history)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
        // Warm path: a press while the app is already running.
        .onChange(of: launch.requestID) { _, newID in
            handleActionButton(newID)
        }
        // Cold path: a press that launched the app (the bump happened before this
        // view existed, so .onChange won't catch it).
        .task {
            handleActionButton(launch.requestID)
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

// MARK: - History

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [DictationEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No dictations yet", systemImage: "clock",
                                       description: Text("Your past dictations will appear here."))
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.displayText)
                        .lineLimit(4)
                    Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Copy") { UIPasteboard.general.string = entry.displayText }
                        .tint(.blue)
                }
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(entries[index]) }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
