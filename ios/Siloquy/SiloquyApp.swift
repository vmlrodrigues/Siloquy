import SwiftUI
import SwiftData

@main
struct SiloquyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: DictationEntry.self)
    }
}
