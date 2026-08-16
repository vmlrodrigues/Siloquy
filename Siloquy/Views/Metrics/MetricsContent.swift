import SwiftUI
import SwiftData
import Foundation
import os

private enum DashboardScope: Hashable {
    case allDevices
    case thisMac
}

private final class DashboardMetricsCache: @unchecked Sendable {
    static let shared = DashboardMetricsCache()

    private let lock = NSLock()
    private var aggregate: DeviceStatsAggregate?

    private init() {}

    func current() -> DeviceStatsAggregate? {
        lock.lock()
        defer { lock.unlock() }
        return aggregate
    }

    func update(_ aggregate: DeviceStatsAggregate) {
        lock.lock()
        self.aggregate = aggregate
        lock.unlock()
    }
}

private enum DashboardMetricsLoader {
    static func load(
        from modelContainer: ModelContainer,
        localDeviceID: String,
        localDeviceName: String
    ) async throws -> DeviceStatsAggregate {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let backgroundContext = ModelContext(modelContainer)
            let aggregate = try DeviceStatsAggregator.aggregate(
                in: backgroundContext,
                localDeviceID: localDeviceID,
                localDeviceName: localDeviceName
            )

            try Task.checkCancellation()

            return aggregate
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

struct MetricsContent: View {
    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "MetricsContent")
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState

    @State private var aggregate: DeviceStatsAggregate = .empty
    @State private var hasLoadedMetricsSnapshot: Bool = false
    @State private var metricsTask: Task<Void, Never>?
    @State private var isModelStatsPanelPresented = false
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @State private var scope: DashboardScope = .allDevices
    /// Device awaiting delete confirmation. Deleting discards session history, so it is
    /// offered only on already-archived devices and never happens on a single click.
    @State private var devicePendingDeletion: DeviceStats?
    /// Archived Macs stay folded away until asked for — they are retired, not interesting.
    @State private var isArchivedGroupExpanded = false

    // The hero and metric cards honour the scope toggle: all active devices combined,
    // or just the Mac being viewed.
    private var totalCount: Int { scope == .thisMac ? (currentDevice?.sessionCount ?? 0) : aggregate.totalSessions }
    private var totalWords: Int { scope == .thisMac ? (currentDevice?.totalWords ?? 0) : aggregate.totalWords }
    private var totalDuration: TimeInterval { scope == .thisMac ? (currentDevice?.totalDuration ?? 0) : aggregate.totalDuration }

    private var currentDevice: DeviceStats? { aggregate.devices.first { $0.isCurrentDevice } }

    // Multi-device chrome only appears when there's more than one device to show.
    private var showConsolidation: Bool { aggregate.devices.count > 1 }
    private var showRoster: Bool { aggregate.devices.count > 1 }
    private var showSplits: Bool { showConsolidation && scope == .allDevices }

    init(modelContext: ModelContext, licenseState: LicenseViewModel.LicenseState) {
        self.modelContext = modelContext
        self.licenseState = licenseState

        let cached = DashboardMetricsCache.shared.current()
        _aggregate = State(initialValue: cached ?? .empty)
        _hasLoadedMetricsSnapshot = State(initialValue: cached != nil)
    }

    var body: some View {
        Group {
            if totalCount == 0 && hasLoadedMetricsSnapshot {
                emptyStateView
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            if !isAccessibilityEnabled {
                                accessibilityPermissionCallout
                            }

                            heroSection

                            if hasLoadedMetricsSnapshot && showConsolidation {
                                scopeControlRow
                            }

                            metricsSection

                            if hasLoadedMetricsSnapshot && showRoster {
                                devicesSection
                            }

                            HStack(alignment: .top, spacing: 18) {
                                HelpAndResourcesSection()
                                DashboardPromotionsSection(licenseState: licenseState)
                            }

                            Spacer(minLength: 4)

                            HStack {
                                Spacer()
                                footerActionsView
                            }
                        }
                        .frame(minHeight: geometry.size.height - 56)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 32)
                    }
                    .background(Color(.windowBackgroundColor))
                }
            }
        }
        .task {
            await loadMetricsEfficiently()
        }
        .onAppear(perform: refreshAccessibilityStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            metricsTask?.cancel()
            metricsTask = Task {
                await loadMetricsEfficiently()
            }
        }
        .onDisappear {
            metricsTask?.cancel()
        }
        .overlay {
            Color.black.opacity(isModelStatsPanelPresented ? 0.1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isModelStatsPanelPresented)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = false }
                }
                .animation(.smooth(duration: 0.3), value: isModelStatsPanelPresented)
        }
        .overlay(alignment: .trailing) {
            if isModelStatsPanelPresented {
                ModelPerformancePanel {
                    withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = false }
                }
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(NSColor.separatorColor)).frame(width: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
                .ignoresSafeArea()
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.3), value: isModelStatsPanelPresented)
        .alert(
            "Delete \(devicePendingDeletion?.deviceName ?? "this Mac")'s history?",
            isPresented: Binding(
                get: { devicePendingDeletion != nil },
                set: { if !$0 { devicePendingDeletion = nil } }
            ),
            presenting: devicePendingDeletion
        ) { device in
            Button("Delete Permanently", role: .destructive) {
                deleteDevice(device)
                devicePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { devicePendingDeletion = nil }
        } message: { device in
            Text("\(Formatters.formattedNumber(device.sessionCount)) sessions and \(Formatters.formattedNumber(device.totalWords)) words will be erased and removed from your totals. This can't be undone.\n\nIf you just want this Mac out of the way, leave it archived — its hours still count.")
        }
    }

    private var accessibilityPermissionCallout: some View {
        PermissionCard(
            icon: "hand.raised",
            title: "Accessibility Access",
            description: "Siloquy needs Accessibility permission to work reliably across your entire Mac",
            isGranted: isAccessibilityEnabled,
            buttonTitle: "Open System Settings",
            buttonAction: openAccessibilitySettings,
            checkPermission: refreshAccessibilityStatus,
            infoTipMessage: "Siloquy uses Accessibility to work reliably across apps."
        )
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func loadMetricsEfficiently() async {
        do {
            let loaded = try await DashboardMetricsLoader.load(
                from: modelContext.container,
                localDeviceID: DeviceIdentity.id,
                localDeviceName: DeviceIdentity.name
            )

            guard !Task.isCancelled else {
                return
            }

            let shouldAccept = loaded.totalSessions > 0 || !SessionMetricMigrationService.shared.isRunning

            await MainActor.run {
                guard shouldAccept else {
                    return
                }

                self.aggregate = loaded
                DashboardMetricsCache.shared.update(loaded)
                self.hasLoadedMetricsSnapshot = true
            }
        } catch is CancellationError {
        } catch {
            logger.error("Error loading metrics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var emptyStateView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    if !isAccessibilityEnabled {
                        accessibilityPermissionCallout
                    }

                    VStack(spacing: 20) {
                        Image(systemName: "waveform")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("No Recorder Sessions Yet")
                            .font(.title3.weight(.semibold))
                        Text("Start your first recording to unlock value insights.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height - 56)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 32)
            }
            .background(Color(.windowBackgroundColor))
        }
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)

                if hasLoadedMetricsSnapshot {
                    (Text("You have saved ")
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.85))
                     +
                     Text(formattedTimeSaved)
                        .fontWeight(.black)
                        .font(.system(size: 36, design: .rounded))
                        .foregroundStyle(.white)
                     +
                     Text(" with Siloquy")
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.85))
                    )
                    .font(.system(size: 30))
                    .multilineTextAlignment(.center)
                } else {
                    Text("Siloquy Insights")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            
            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 16)
    }
    
    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            MetricCard(
                icon: "mic.fill",
                title: "Sessions Recorded",
                value: hasLoadedMetricsSnapshot ? "\(totalCount)" : "–",
                detail: "Siloquy sessions completed",
                color: .purple,
                footer: showSplits ? splitBar { Double($0.sessionCount) } : nil
            )

            MetricCard(
                icon: "text.alignleft",
                title: "Words Dictated",
                value: hasLoadedMetricsSnapshot ? Formatters.formattedNumber(totalWords) : "–",
                detail: "words generated",
                color: Color(nsColor: .controlAccentColor),
                footer: showSplits ? splitBar { Double($0.totalWords) } : nil
            )

            MetricCard(
                icon: "speedometer",
                title: "Words Per Minute",
                value: hasLoadedMetricsSnapshot && averageWordsPerMinute > 0
                    ? String(format: "%.1f", averageWordsPerMinute)
                    : "–",
                detail: "Siloquy vs. typing by hand",
                color: .yellow,
                footer: showSplits ? perMacWordsPerMinuteFooter : nil
            )

            MetricCard(
                icon: "keyboard.fill",
                title: "Keystrokes Saved",
                value: hasLoadedMetricsSnapshot ? Formatters.formattedNumber(totalKeystrokesSaved) : "–",
                detail: "fewer keystrokes",
                color: .orange,
                footer: showSplits ? splitBar { Double($0.keystrokesSaved) } : nil
            )
        }
    }

    private var scopeControlRow: some View {
        HStack(spacing: 9) {
            Text(scopeCaption)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(aggregate.devices) { device in
                    Circle()
                        .fill(deviceColor(for: device))
                        .frame(width: 8, height: 8)
                        .opacity(device.isArchived ? 0.4 : 1)
                }
            }

            Spacer(minLength: 8)

            Picker("", selection: $scope) {
                Text("All devices").tag(DashboardScope.allDevices)
                Text("This Mac").tag(DashboardScope.thisMac)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var scopeCaption: String {
        switch scope {
        case .allDevices: return "Combined across \(aggregate.devices.count) Macs"
        case .thisMac: return "Showing this Mac only"
        }
    }

    /// A per-device split bar (segment widths proportional to each active device's value).
    private func splitBar(_ value: @escaping (DeviceStats) -> Double) -> AnyView {
        AnyView(
            DeviceSplitBar(segments: aggregate.devices.map {
                DeviceSplitBar.Segment(color: deviceColor(for: $0), value: value($0))
            })
        )
    }

    /// WPM is a rate, not a sum, so it shows the weighted average plus each Mac's own figure.
    private var perMacWordsPerMinuteFooter: AnyView {
        var text = Text("Weighted avg · ").foregroundColor(.secondary)
        for (index, device) in aggregate.devices.enumerated() {
            if index > 0 { text = text + Text(" / ").foregroundColor(.secondary) }
            text = text + Text("\(Int(device.wordsPerMinute.rounded()))").foregroundColor(deviceColor(for: device))
        }
        text = text + Text(" per Mac").foregroundColor(.secondary)
        return AnyView(text.font(.system(size: 11)))
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .foregroundColor(.secondary)
                Text("Devices")
                    .font(.system(size: 16, weight: .semibold))
                // Counts the Macs in the list. Archived ones are tucked into their own
                // collapsed group below and carry their own count.
                if aggregate.activeDevices.count > 1 {
                    Text("\(aggregate.activeDevices.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Spacer()
            }

            VStack(spacing: 10) {
                ForEach(aggregate.activeDevices) { device in
                    DeviceStatRow(
                        device: device,
                        color: deviceColor(for: device),
                        onArchive: { archiveDevice(device) },
                        onRestore: { restoreDevice(device) },
                        onDelete: { devicePendingDeletion = device }
                    )
                }

                if !aggregate.archivedDevices.isEmpty { archivedGroup }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Archived Macs, folded away behind a single quiet row.
    ///
    /// They still count toward the totals, so they can't simply vanish — but they are
    /// retired hardware and shouldn't take up space in the list every day. Collapsed by
    /// default, one click to open, restore and delete live inside. No separate screen:
    /// undoing a mistaken archive should not be a hunt.
    private var archivedGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.22)) { isArchivedGroupExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isArchivedGroupExpanded ? 90 : 0))
                    Image(systemName: "archivebox")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(archivedSummary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isArchivedGroupExpanded ? "Hide archived Macs" : "Show archived Macs, and restore any you archived by mistake")

            if isArchivedGroupExpanded {
                ForEach(aggregate.archivedDevices) { device in
                    DeviceStatRow(
                        device: device,
                        color: deviceColor(for: device),
                        onArchive: { archiveDevice(device) },
                        onRestore: { restoreDevice(device) },
                        onDelete: { devicePendingDeletion = device }
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
    }

    /// Names the archived Macs when there are few enough to read at a glance, so the row
    /// is useful without being opened.
    private var archivedSummary: String {
        let archived = aggregate.archivedDevices
        let count = archived.count
        let noun = count == 1 ? "archived Mac" : "archived Macs"
        guard count <= 2 else { return "\(count) \(noun)" }
        return "\(count) \(noun) — \(archived.map(\.deviceName).joined(separator: ", "))"
    }

    /// Stable per-device accent. The current Mac is always teal; others get a
    /// deterministic colour from the palette (djb2 over the deviceID, so it
    /// never changes between launches or reorderings).
    private func deviceColor(for device: DeviceStats) -> Color {
        if device.isCurrentDevice {
            return Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255) // #2DD4BF
        }
        let palette: [Color] = [
            Color(red: 251 / 255, green: 113 / 255, blue: 133 / 255), // #FB7185 rose
            Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255), // #A78BFA violet
            Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255),  // #FBBF24 amber
            Color(red: 56 / 255,  green: 189 / 255, blue: 248 / 255)  // #38BDF8 sky
        ]
        let hash = device.deviceID.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) }
        return palette[Int(hash % UInt32(palette.count))]
    }

    private func archiveDevice(_ device: DeviceStats) {
        let tombstone = ArchivedDevice(
            deviceID: device.deviceID,
            deviceName: device.deviceName,
            archivedAt: Date()
        )
        modelContext.insert(tombstone)
        persistDeviceChangeAndReload()
    }

    private func restoreDevice(_ device: DeviceStats) {
        let targetID = device.deviceID
        let descriptor = FetchDescriptor<ArchivedDevice>(
            predicate: #Predicate { $0.deviceID == targetID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            for record in existing { modelContext.delete(record) }
        }
        persistDeviceChangeAndReload()
    }

    /// Permanently discard a device's session history.
    ///
    /// The counterpart to archiving: archiving tidies a retired Mac out of the list while
    /// keeping its hours in the lifetime totals; deleting says the dictation should never
    /// have counted — a test rig, a loaner, someone else's Mac. Irreversible, so it is
    /// offered only on archived devices and only behind a confirmation.
    private func deleteDevice(_ device: DeviceStats) {
        let targetID = device.deviceID

        var removed = 0
        do {
            let metrics = FetchDescriptor<SessionMetric>(
                predicate: #Predicate { $0.deviceID == targetID }
            )
            var records = try modelContext.fetch(metrics)

            // `deviceID` is optional, so the predicate compares String? to String. That
            // holds for every record written today, but a store with un-attributed rows
            // would quietly match nothing — and a delete that silently removes zero rows
            // looks exactly like a broken button. Fall back to filtering in memory rather
            // than reporting a success that didn't happen.
            if records.isEmpty && device.sessionCount > 0 {
                logger.notice("Predicate matched no metrics for a device claiming \(device.sessionCount, privacy: .public) sessions; falling back to an in-memory scan.")
                records = try modelContext.fetch(FetchDescriptor<SessionMetric>())
                    .filter { $0.deviceID == targetID }
            }

            for record in records {
                modelContext.delete(record)
                removed += 1
            }
        } catch {
            logger.error("Failed to fetch metrics for deletion: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Drop the tombstone too, so a device that starts recording again comes back
        // clean rather than reappearing pre-archived.
        let tombstones = FetchDescriptor<ArchivedDevice>(
            predicate: #Predicate { $0.deviceID == targetID }
        )
        if let records = try? modelContext.fetch(tombstones) {
            for record in records { modelContext.delete(record) }
        }

        logger.notice("Deleted \(removed, privacy: .public) of \(device.sessionCount, privacy: .public) expected session metrics for archived device")
        // Collapse the group if that was the last archived Mac, so an empty
        // disclosure row isn't left behind.
        if aggregate.archivedDevices.count <= 1 { isArchivedGroupExpanded = false }
        persistDeviceChangeAndReload()
    }

    private func persistDeviceChangeAndReload() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to persist device archive change: \(error.localizedDescription, privacy: .public)")
        }
        metricsTask?.cancel()
        metricsTask = Task { await loadMetricsEfficiently() }
    }

    private var footerActionsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = true }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge")
                    Text("Model Performance")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.thinMaterial))
            }
            .buttonStyle(.plain)
            .help("View transcription and enhancement model performance")
            CopySystemInfoButton()
        }
    }
    
    private var formattedTimeSaved: String {
        let formatted = Formatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings coming soon")
        return formatted
    }
    
    private var heroSubtitle: String {
        guard hasLoadedMetricsSnapshot else {
            return "Your usage summary will appear here."
        }

        guard totalCount > 0 else {
            return "Your Siloquy journey starts with your first recording."
        }

        let wordsText = Formatters.formattedNumber(totalWords)
        let sessionText = totalCount == 1 ? "session" : "sessions"
        let base = "Dictated \(wordsText) words across \(totalCount) \(sessionText)."

        if showSplits {
            return base + " Combined from \(aggregate.devices.count) Macs."
        }
        return base
    }
    
    private var heroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(nsColor: .controlAccentColor),
                Color(nsColor: .controlAccentColor).opacity(0.85),
                Color(nsColor: .controlAccentColor).opacity(0.7)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Computed Metrics

    private var estimatedTypingTime: TimeInterval {
        let averageTypingSpeed: Double = 35 // words per minute
        let estimatedTypingTimeInMinutes = Double(totalWords) / averageTypingSpeed
        return estimatedTypingTimeInMinutes * 60
    }

    private var timeSaved: TimeInterval {
        max(estimatedTypingTime - totalDuration, 0)
    }

    private var averageWordsPerMinute: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalWords) / (totalDuration / 60.0)
    }

    private var totalKeystrokesSaved: Int {
        Int(Double(totalWords) * 5.0)
    }
    
}

private struct DeviceSplitBar: View {
    struct Segment {
        let color: Color
        let value: Double
    }
    let segments: [Segment]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        let gap: CGFloat = 2
        GeometryReader { geo in
            let available = max(0, geo.size.width - gap * CGFloat(max(segments.count - 1, 0)))
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.color)
                        .frame(width: available * CGFloat(segment.value / total))
                }
            }
        }
        .frame(height: 5)
    }
}

private struct DeviceStatRow: View {
    let device: DeviceStats
    let color: Color
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    /// A non-current device that hasn't recorded in over 30 days — a hint that it may
    /// be worth archiving. The current Mac is never stale.
    private var isStale: Bool {
        guard !device.isCurrentDevice, !device.isArchived else { return false }
        return device.lastActive < Date().addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private var statLine: String {
        let sessions = "\(device.sessionCount) \(device.sessionCount == 1 ? "session" : "sessions")"
        let words = "\(Formatters.formattedNumber(device.totalWords)) words"
        if device.wordsPerMinute > 0 {
            return "\(sessions) · \(words) · \(String(format: "%.0f", device.wordsPerMinute)) WPM"
        }
        return "\(sessions) · \(words)"
    }

    private var lastActiveText: String {
        guard device.lastActive > .distantPast else { return "No sessions yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Active \(formatter.localizedString(for: device.lastActive, relativeTo: Date()))"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if device.isCurrentDevice { badge("This Mac", Color(nsColor: .controlAccentColor)) }
                    if device.isArchived {
                        badge("Archived", .secondary)
                    } else if isStale {
                        badge("Stale", .orange)
                    }
                }
                Text(statLine)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(lastActiveText)
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .opacity(device.isArchived ? 0.6 : 1)

            Spacer(minLength: 8)

            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder private var actionButton: some View {
        if device.isArchived {
            HStack(spacing: 14) {
                Button("Restore", action: onRestore)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .controlAccentColor))
                    .help("Move this Mac back into the active list")
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Permanently erase this Mac's sessions and remove them from your totals")
            }
        } else if !device.isCurrentDevice {
            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Archive this Mac — tidies it out of the list, keeps its hours in your totals")
        }
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private enum Formatters {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        return formatter
    }()
    
    static func formattedNumber(_ value: Int) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    static func formattedDuration(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle, fallback: String = "–") -> String {
        guard interval > 0 else { return fallback }
        durationFormatter.unitsStyle = style
        durationFormatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        return durationFormatter.string(from: interval) ?? fallback
    }
}

private struct CopySystemInfoButton: View {
    @State private var isCopied: Bool = false

    var body: some View {
        Button(action: {
            copySystemInfo()
        }) {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .rotationEffect(.degrees(isCopied ? 360 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)

                Text(isCopied ? "Copied!" : "Copy System Info")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .scaleEffect(isCopied ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
    }

    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCopied = false
            }
        }
    }
}
