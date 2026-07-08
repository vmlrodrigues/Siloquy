import Foundation
import SwiftData

@Model
final class SessionMetric {
    var id: UUID = UUID()
    var transcriptionId: UUID = UUID()
    var timestamp: Date = Date()
    var source: String?
    var wordCount: Int = 0
    var audioDuration: TimeInterval = 0
    var transcriptionModelName: String?
    var transcriptionDuration: TimeInterval?
    var speedFactor: Double?
    var powerModeName: String?
    var aiEnhancementModelName: String?
    var enhancementDuration: TimeInterval?
    var deviceID: String?
    var deviceName: String?

    init(
        transcriptionId: UUID,
        timestamp: Date = Date(),
        source: String? = "recorder",
        wordCount: Int,
        audioDuration: TimeInterval,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        speedFactor: Double?,
        powerModeName: String?,
        aiEnhancementModelName: String?,
        enhancementDuration: TimeInterval?,
        deviceID: String? = nil,
        deviceName: String? = nil
    ) {
        self.id = UUID()
        self.transcriptionId = transcriptionId
        self.timestamp = timestamp
        self.source = source
        self.wordCount = wordCount
        self.audioDuration = audioDuration
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.speedFactor = speedFactor
        self.powerModeName = powerModeName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
        // Stamp the record with its origin machine so synced stats can be attributed
        // per-device and aggregated in the UI. Defaults to this Mac unless explicitly set.
        self.deviceID = deviceID ?? DeviceIdentity.id
        self.deviceName = deviceName ?? DeviceIdentity.name
    }
}
