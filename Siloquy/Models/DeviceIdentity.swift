import Foundation
import SystemConfiguration

/// Stable identity for this Mac, used to attribute synced statistics to the machine that
/// produced them. The id is generated once and persisted; the name reflects the Mac's
/// current "Computer Name" from Sharing settings.
enum DeviceIdentity {
    private static let idKey = "deviceIdentityID"

    /// A stable per-installation UUID. Generated on first access, then persisted.
    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: idKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: idKey)
        return generated
    }

    /// A human-friendly name for this Mac (e.g. "Mac Studio"), falling back to the host name.
    static var name: String {
        if let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            return computerName
        }
        return Host.current().localizedName ?? "Mac"
    }
}
