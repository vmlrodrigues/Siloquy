import Foundation
import SwiftData
import OSLog

/// One-time migration that stamps pre-existing `SessionMetric` records — those created
/// before per-device attribution existed — with THIS Mac's device identity.
///
/// This must run before CloudKit can export those records: an un-attributed (`nil`
/// deviceID) record synced from one Mac would be imported by another Mac and counted as
/// its own. Running it synchronously during container setup guarantees it completes before
/// the first mirror export, so nothing un-attributed ever reaches the cloud.
enum SessionMetricDeviceBackfill {
    private static let completionKey = "HasBackfilledSessionMetricDeviceIDs"
    private static let logger = Logger(
        subsystem: "com.victorrodrigues.siloquy",
        category: "SessionMetricDeviceBackfill"
    )

    static func runIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: completionKey) else { return }

        let context = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<SessionMetric>(
                predicate: #Predicate { $0.deviceID == nil }
            )
            let orphans = try context.fetch(descriptor)

            if !orphans.isEmpty {
                let id = DeviceIdentity.id
                let name = DeviceIdentity.name
                for metric in orphans {
                    metric.deviceID = id
                    metric.deviceName = name
                }
                try context.save()
                logger.notice("Stamped \(orphans.count, privacy: .public) pre-attribution session metrics with this device's identity.")
            }

            UserDefaults.standard.set(true, forKey: completionKey)
        } catch {
            // Leave the flag unset so it retries next launch rather than syncing nils.
            logger.error("Device backfill failed, will retry next launch: \(error.localizedDescription, privacy: .public)")
        }
    }
}
