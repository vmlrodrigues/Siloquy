import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import Carbon
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "AppDelegate")
    private let launchDate = Date()
    /// Set when the initial window was suppressed on the menu-bar-only heuristic rather
    /// than a definitive login-item Apple event. macOS activates a manually launched app
    /// moments after launch; login-item and reboot state-restoration launches stay in the
    /// background. When that early activation arrives we reveal the window, so a
    /// deliberate launch still shows the app while background launches stay hidden.
    private var revealSuppressedWindowOnActivation = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Definitive login-item launch signal (legacy Apple event). Reliable when present,
        // but SMAppService/launchd and reboot state-restoration launches frequently omit
        // it, so it can't be the only trigger (issue #10).
        let launchedAsLoginItem: Bool = {
            guard let event = NSAppleEventManager.shared().currentAppleEvent,
                  event.eventID == AEEventID(kAEOpenApplication),
                  event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
            else { return false }
            return true
        }()

        // Hide Dock Icon (menu-bar-only) means the app should never start with a Dock
        // icon, regardless of how the launch happened — the launch type only decides
        // whether the main window is revealed (see applicationDidBecomeActive).
        let isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")

        // Only suppress the post-onboarding main window. If onboarding isn't finished,
        // launch normally so the onboarding flow stays visible.
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        guard launchedAsLoginItem || isMenuBarOnly else { return }

        // Start in the background — no main window, no Dock icon (only the menu-bar
        // icon). configureWindow orders the auto-created window out.
        logger.notice("willFinishLaunching: suppressing initial window (loginItemEvent=\(launchedAsLoginItem, privacy: .public), menuBarOnly=\(isMenuBarOnly, privacy: .public))")
        WindowManager.shared.suppressInitialWindow = true
        NSApp.setActivationPolicy(.accessory)
        if !launchedAsLoginItem {
            revealSuppressedWindowOnActivation = true
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard revealSuppressedWindowOnActivation else { return }
        revealSuppressedWindowOnActivation = false
        // Only an activation that is part of the launch itself marks a manual launch.
        // Later activations (opening History from the menu bar, a reopen hours after a
        // login launch) must not pop the main window.
        let sinceLaunch = Date().timeIntervalSince(launchDate)
        guard sinceLaunch < 5 else {
            logger.notice("didBecomeActive: reveal window expired (+\(sinceLaunch, format: .fixed(precision: 1), privacy: .public)s), leaving main window hidden")
            return
        }
        logger.notice("didBecomeActive: manual launch detected (+\(sinceLaunch, format: .fixed(precision: 1), privacy: .public)s), revealing main window")
        if WindowManager.shared.showMainWindow() == nil {
            // The launch activation can arrive before SwiftUI has created the window
            // (observed ~0.6s in). showMainWindow has already cleared the suppression
            // flag, so configureWindow will order the window in normally — but the app
            // is still .accessory, which drops the Dock icon and lets the activation
            // fizzle (the app appears to launch unfocused). Restore a normal-launch
            // environment now; the window then comes up focused, Dock icon steady.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            logger.notice("didBecomeActive: window not created yet — restored .regular for a normal launch")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentionally does NOT touch the activation policy. The app launches at its
        // default policy and MenuBarManager's window open/close handlers drive it from
        // there. Forcing .accessory at launch — while the WindowGroup opens its window
        // and flips to .regular — made macOS spawn a DUPLICATE Dock tile for the single
        // running app (menu-bar-only mode). Window-driven transitions don't churn.
        #if LOCAL_BUILD
        // Dev build (`make local`): badge the Dock tile so it's obvious at a glance
        // which build is running. Release builds don't compile this in.
        NSApp.dockTile.badgeLabel = "DEV"
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The user re-opened the app (Finder/Spotlight/Launchpad) with no window visible:
        // show the main window explicitly. This also covers menu-bar-only mode, where the
        // initial window is suppressed at launch — windowDidBecomeKey then restores the
        // Dock icon for as long as the window stays open.
        if !flag {
            if WindowManager.shared.showMainWindow() != nil {
                return false
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Stash URL when app cold-starts to avoid spawning a new window/tab
    var pendingOpenFileURL: URL?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { SupportedMedia.isSupported(url: $0) }) else {
            return
        }
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        if WindowManager.shared.currentMainWindow() == nil {
            // Cold start: do NOT create a window here to avoid extra window/tab.
            // Defer to SwiftUI’s WindowGroup-created ContentView and let it process this later.
            pendingOpenFileURL = url
        } else {
            // Running: focus current window and route in-place to Transcribe Audio
            menuBarManager?.focusMainWindow()
            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": url])
            }
        }
    }
}
