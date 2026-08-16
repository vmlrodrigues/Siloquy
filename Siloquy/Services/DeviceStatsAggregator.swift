import Foundation
import SwiftData

/// Rolled-up statistics for a single device (one Mac), derived from its `SessionMetric` records.
struct DeviceStats: Identifiable, Equatable, Sendable {
    let deviceID: String
    var deviceName: String
    var sessionCount: Int
    var totalWords: Int
    /// Summed audio duration — the basis for words-per-minute.
    var totalDuration: TimeInterval
    /// Newest session timestamp for this device — the basis for staleness.
    var lastActive: Date
    var isArchived: Bool
    /// True for the Mac currently viewing the dashboard.
    var isCurrentDevice: Bool

    var id: String { deviceID }

    /// Duration-weighted words per minute for this device.
    var wordsPerMinute: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalWords) / (totalDuration / 60.0)
    }

    /// Estimated keystrokes saved (≈5 keystrokes per word), matching the dashboard's model.
    var keystrokesSaved: Int { Int(Double(totalWords) * 5.0) }
}

/// The full cross-device aggregation: every known device plus combined lifetime totals.
struct DeviceStatsAggregate: Equatable, Sendable {
    /// Every device that has recorded a session (plus any archived tombstone),
    /// sorted current-device-first, then most-recently-active first.
    var devices: [DeviceStats]

    var activeDevices: [DeviceStats] { devices.filter { !$0.isArchived } }
    var archivedDevices: [DeviceStats] { devices.filter { $0.isArchived } }

    // MARK: Combined totals — every device, archived included

    // Archiving is a presentation choice: it tidies a retired Mac out of the device
    // list. It is not a claim that the dictation never happened, so the lifetime
    // figures keep counting it. Replacing a Mac should not erase the hours it saved.
    // Removing a device from the totals is what Delete is for.

    var totalSessions: Int { devices.reduce(0) { $0 + $1.sessionCount } }
    var totalWords: Int { devices.reduce(0) { $0 + $1.totalWords } }
    var totalDuration: TimeInterval { devices.reduce(0) { $0 + $1.totalDuration } }

    /// Combined WPM is the duration-weighted average — total words over total speaking
    /// time. Summing or averaging per-device WPM values would be wrong.
    var averageWordsPerMinute: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalWords) / (totalDuration / 60.0)
    }

    var totalKeystrokesSaved: Int { Int(Double(totalWords) * 5.0) }

    static let empty = DeviceStatsAggregate(devices: [])
}

/// Builds a per-device breakdown of session statistics from the stats store.
///
/// Every `SessionMetric` is attributed to a device via its `deviceID`. Records that
/// predate per-device attribution (nil `deviceID`) are treated as belonging to the
/// local Mac — on any given machine, its own un-attributed history is its own.
/// Devices named in the `ArchivedDevice` tombstone table are flagged `isArchived` so the
/// UI can group them separately, but they still count toward the combined lifetime totals.
enum DeviceStatsAggregator {

    static func aggregate(
        in context: ModelContext,
        localDeviceID: String,
        localDeviceName: String
    ) throws -> DeviceStatsAggregate {
        // 1. Which devices have been archived?
        let archived = try context.fetch(FetchDescriptor<ArchivedDevice>())
        let archivedIDs = Set(archived.map(\.deviceID))
        var archivedNames: [String: String] = [:]
        for record in archived where !record.deviceName.isEmpty {
            archivedNames[record.deviceID] = record.deviceName
        }

        // 2. Roll up SessionMetric by device.
        struct Accumulator {
            var name: String = ""
            var sessions: Int = 0
            var words: Int = 0
            var duration: TimeInterval = 0
            var lastActive: Date = .distantPast
        }
        var byDevice: [String: Accumulator] = [:]

        var descriptor = FetchDescriptor<SessionMetric>()
        descriptor.propertiesToFetch = [\.deviceID, \.deviceName, \.wordCount, \.audioDuration, \.timestamp]

        try context.enumerate(descriptor) { metric in
            let id = metric.deviceID ?? localDeviceID
            var acc = byDevice[id] ?? Accumulator()
            // Keep the most recent non-empty stored name for this device.
            if let name = metric.deviceName, !name.isEmpty { acc.name = name }
            acc.sessions += 1
            acc.words += metric.wordCount
            acc.duration += metric.audioDuration
            if metric.timestamp > acc.lastActive { acc.lastActive = metric.timestamp }
            byDevice[id] = acc
        }

        // 3. Surface archived devices that have no live sessions in this store.
        for (id, name) in archivedNames where byDevice[id] == nil {
            byDevice[id] = Accumulator(name: name)
        }

        // 4. Materialise, resolving a display name for every device.
        var devices: [DeviceStats] = byDevice.map { id, acc in
            let resolvedName: String
            if !acc.name.isEmpty {
                resolvedName = acc.name
            } else if id == localDeviceID {
                resolvedName = localDeviceName
            } else if let archivedName = archivedNames[id] {
                resolvedName = archivedName
            } else {
                resolvedName = "Unknown Mac"
            }

            return DeviceStats(
                deviceID: id,
                deviceName: resolvedName,
                sessionCount: acc.sessions,
                totalWords: acc.words,
                totalDuration: acc.duration,
                lastActive: acc.lastActive,
                isArchived: archivedIDs.contains(id),
                isCurrentDevice: id == localDeviceID
            )
        }

        // 5. Current device first, then most-recently-active.
        devices.sort { lhs, rhs in
            if lhs.isCurrentDevice != rhs.isCurrentDevice { return lhs.isCurrentDevice }
            return lhs.lastActive > rhs.lastActive
        }

        return DeviceStatsAggregate(devices: devices)
    }
}
