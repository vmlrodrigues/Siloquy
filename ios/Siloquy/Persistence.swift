import SwiftData

/// A single shared SwiftData store used by *both* the SwiftUI app and the
/// background dictation controller.
///
/// `BackgroundDictationController` is a `static let shared` singleton that lives
/// outside the SwiftUI view hierarchy (it runs from an AppIntent, often while the
/// app is backgrounded), so it has no `@Environment(\.modelContext)`. It writes
/// through this container instead. Because the app's `@Query` observes the *same*
/// container, entries saved from the background appear in history immediately.
enum Persistence {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: DictationEntry.self)
        } catch {
            fatalError("Failed to create the Siloquy model container: \(error)")
        }
    }()
}
