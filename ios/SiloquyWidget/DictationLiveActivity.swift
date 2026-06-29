import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Live Activity for background dictation: shows recording state on the Lock
/// Screen and in the Dynamic Island, with an interactive Stop button.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Siloquy").font(.caption.weight(.semibold))
                    Text(context.state.status).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                stopButton
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Siloquy", systemImage: "waveform").foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .monospacedDigit().frame(maxWidth: 56)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.status).font(.subheadline)
                        Spacer()
                        stopButton
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(.red)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(.red)
            }
        }
    }

    private var stopButton: some View {
        Button(intent: StopDictationIntent()) {
            Label("Stop", systemImage: "stop.fill")
        }
        .tint(.red)
        .font(.caption.weight(.semibold))
    }
}
