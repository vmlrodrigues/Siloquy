import SwiftUI
import SwiftData

@main
struct SiloquyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Persistence.container)
        // Warm the mic pipeline while foreground so the first Action Button press
        // records reliably from the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                BackgroundDictationController.shared.warmUpSession()
            }
        }
    }
}
