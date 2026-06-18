import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Detect a login-item (startup) launch via the open-application Apple event. Read here
        // because that event is only the "current" Apple event this early in launch.
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        else { return }

        // Only suppress the post-onboarding main window. If onboarding isn't finished, launch
        // normally so the onboarding flow stays visible.
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }

        // Launched at login: start in the background — no main window, no Dock icon (only the
        // menu-bar icon). configureWindow orders the auto-created window out. A manual launch
        // never reaches here, so its window/Dock behaviour is unchanged.
        WindowManager.shared.suppressInitialWindow = true
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentionally does NOT touch the activation policy. The app launches at its
        // default policy and MenuBarManager's window open/close handlers drive it from
        // there. Forcing .accessory at launch — while the WindowGroup opens its window
        // and flips to .regular — made macOS spawn a DUPLICATE Dock tile for the single
        // running app (menu-bar-only mode). Window-driven transitions don't churn.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let menuBarManager = menuBarManager, !menuBarManager.isMenuBarOnly {
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
