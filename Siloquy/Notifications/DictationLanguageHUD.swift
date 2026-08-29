import AppKit
import SwiftUI

/// A brief flag-and-name flash under the notch when the dictation language changes.
///
/// The shortcut is global, so most switches happen while you are in another app with
/// nothing of Siloquy's on screen. Without this you press a key and get no
/// acknowledgement at all, then find out which language you were in only after you have
/// finished speaking — the same "too late to be useful" failure the download prompt
/// exists to avoid.
@MainActor
final class DictationLanguageHUD {
    static let shared = DictationLanguageHUD()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ language: DictationLanguage) {
        dismissTask?.cancel()
        dismissTask = nil

        let hosting = NSHostingController(rootView: DictationLanguageHUDView(language: language))
        hosting.view.frame = NSRect(x: 0, y: 0, width: 210, height: 44)

        let panel = existingPanel() ?? makePanel()
        panel.contentViewController = hosting
        panel.setFrame(Self.frame(width: 210, height: 44), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }

    private func existingPanel() -> NSPanel? { panel }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: Self.frame(width: 210, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the notch recorder, so a switch is still visible if the recorder is up.
        panel.level = .statusBar + 4
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    /// Centred under the notch (or under the menu bar on a screen without one), so it
    /// reads as coming from the same place the recorder does.
    private static func frame(width: CGFloat, height: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }
        let topInset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - topInset - height - 6,
            width: width,
            height: height
        )
    }
}

/// Never takes focus: switching language must not pull you out of what you are typing in.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct DictationLanguageHUDView: View {
    let language: DictationLanguage

    var body: some View {
        HStack(spacing: 10) {
            Text(language.flag)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 0) {
                Text(language.nativeName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Dictation language")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 210, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
