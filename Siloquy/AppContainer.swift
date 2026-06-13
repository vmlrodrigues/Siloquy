import Foundation

/// Single source of truth for where this build keeps its data under Application Support.
///
/// Dev builds (`LOCAL_BUILD`) use a `.dev`-suffixed directory so they never share
/// SwiftData stores (history, dictionary, stats), downloaded Whisper models, or
/// recordings with the released app — a dev-side schema migration can't touch the
/// real store. Only on-disk data is sandboxed: logging subsystems, the Keychain
/// service id, and the iCloud container keep the release identifier.
///
/// Note: the Parakeet model lives in FluidAudio's own cache, not here, so the dev
/// sandbox does not trigger a model re-download.
enum AppContainer {
    /// Directory name under ~/Library/Application Support for this build's data.
    static let directoryName: String = {
        #if LOCAL_BUILD
        return "com.victorrodrigues.siloquy.dev"
        #else
        return "com.victorrodrigues.siloquy"
        #endif
    }()

    /// ~/Library/Application Support/<directoryName>
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }
}
