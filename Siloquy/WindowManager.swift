import SwiftUI
import AppKit
import OSLog

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.victorrodrigues.siloquy.mainWindow")
    private static let onboardingWindowIdentifier = NSUserInterfaceItemIdentifier("com.victorrodrigues.siloquy.onboardingWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("SiloquyMainWindowFrame")

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "WindowManager")
    private weak var mainWindow: NSWindow?
    private var didApplyInitialPlacement = false
    /// Set when the app was launched as a login item: configureWindow then keeps the
    /// auto-created main window hidden (no Dock icon) so the app starts in the background.
    /// Cleared the moment the window is shown explicitly (showMainWindow).
    var suppressInitialWindow = false

    private override init() {
        super.init()
    }
    
    func configureWindow(_ window: NSWindow) {
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier && $0 != window }) {
            logger.notice("configureWindow: duplicate detected, reusing existing window")
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        logger.notice("configureWindow: registering main window")
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        // CFBundleName is "Siloquy Dev" in `make local` builds — keeps Mission Control
        // and the window switcher honest about which build this is.
        window.title = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Siloquy"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 0, height: 0)
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        applyInitialPlacementIfNeeded(to: window)
        registerMainWindowIfNeeded(window)

        if suppressInitialWindow {
            // Background (login-item / menu-bar-only) launch: keep the app in the
            // background — no window, no Dock icon. The window stays registered so the
            // menu bar can show it on demand later. The flag is consumed here: it only
            // guards the initial auto-created window, and leaving it set would block
            // windowDidBecomeKey from restoring the Dock icon on a later reopen.
            logger.notice("configureWindow: background launch — keeping main window hidden")
            NSApp.setActivationPolicy(.accessory)
            window.orderOut(nil)
            suppressInitialWindow = false
        } else {
            window.orderFrontRegardless()
            clearInitialFocus(from: window)
        }
    }
    
    func configureOnboardingPanel(_ window: NSWindow) {
        if window.identifier == nil || window.identifier != Self.onboardingWindowIdentifier {
            window.identifier = Self.onboardingWindowIdentifier
        }
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "Siloquy Onboarding"
        window.isOpaque = false
        window.minSize = NSSize(width: 900, height: 780)
        window.makeKeyAndOrderFront(nil)
        clearInitialFocus(from: window)
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
    }
    
    func showMainWindow() -> NSWindow? {
        // An explicit show cancels any pending login-item suppression.
        suppressInitialWindow = false
        guard let window = resolveMainWindow() else {
            return nil
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
    }
    
    func hideMainWindow() {
        guard let window = resolveMainWindow() else {
            return
        }
        window.orderOut(nil)
    }

    /// Clear any control that grabbed keyboard focus when the window first appeared, so the
    /// macOS focus ring isn't shown on launch (a pre-existing VoiceInk behaviour). The user's
    /// first Tab re-engages keyboard focus and the ring returns, so keyboard accessibility is
    /// preserved — only the unsolicited launch-time ring is removed.
    private func clearInitialFocus(from window: NSWindow) {
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
    }
    
    func currentMainWindow() -> NSWindow? {
        resolveMainWindow()
    }
    
    private func registerMainWindowIfNeeded(_ window: NSWindow) {
        // Only register the primary content window, identified by the hidden title bar style
        if window.identifier == nil || window.identifier != Self.mainWindowIdentifier {
            registerMainWindow(window)
        }
    }
    
    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }
        // Attempt to restore previous frame if one exists; otherwise fall back to a centered placement
        if !window.setFrameUsingName(Self.mainWindowAutosaveName) {
            window.center()
        }
        didApplyInitialPlacement = true
    }
    
    private func resolveMainWindow() -> NSWindow? {
        if let window = mainWindow {
            return window
        }

        logger.notice("resolveMainWindow: weak ref is nil, searching \(NSApplication.shared.windows.count, privacy: .public) windows by identifier")

        if let window = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier }) {
            logger.notice("resolveMainWindow: recovered window via identifier fallback")
            mainWindow = window
            window.delegate = self
            return window
        }

        let windowIDs = NSApplication.shared.windows.map { $0.identifier?.rawValue ?? "nil" }.joined(separator: ", ")
        logger.error("resolveMainWindow: FAILED — no window found with main identifier. Total windows: \(NSApplication.shared.windows.count, privacy: .public), identifiers: \(windowIDs, privacy: .public)")
        return nil
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.identifier == Self.mainWindowIdentifier {
            logger.notice("windowWillClose: main window closing, clearing weak reference")
            window.orderOut(nil)
            mainWindow = nil
            didApplyInitialPlacement = false
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
} 
