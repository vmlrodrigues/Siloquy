import Foundation

/// A persistent breadcrumb log for debugging the background dictation flow
/// without device-log access. Each step is appended and saved to UserDefaults,
/// so it survives the background process being killed and can be read back in
/// the app UI after a test.
@MainActor
final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    private let key = "bgDiagnosticLog"
    @Published private(set) var lines: [String] = []

    private init() {
        refresh()
    }

    /// Re-read from UserDefaults (the background process may have appended while
    /// the foreground app was suspended / in another process).
    func refresh() {
        lines = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func log(_ message: String) {
        let line = "\(Self.formatter.string(from: Date()))  \(message)"
        var stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        stored.append(line)
        if stored.count > 300 { stored.removeFirst(stored.count - 300) }
        UserDefaults.standard.set(stored, forKey: key)
        lines = stored
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        lines = []
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
