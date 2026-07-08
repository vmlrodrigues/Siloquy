import Foundation
import SwiftData

/// A tombstone marking a device whose statistics should be excluded from the combined
/// totals. Syncs via CloudKit so every Mac agrees on which devices are archived.
///
/// This is a *soft* removal — no `SessionMetric` records are deleted, so archiving is fully
/// reversible: delete the tombstone and the device rejoins the totals. All properties have
/// defaults so the model stays CloudKit-compatible.
@Model
final class ArchivedDevice {
    var deviceID: String = ""
    var deviceName: String = ""
    var archivedAt: Date = Date()

    init(deviceID: String, deviceName: String = "", archivedAt: Date = Date()) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.archivedAt = archivedAt
    }
}
