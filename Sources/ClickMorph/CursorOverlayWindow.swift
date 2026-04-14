import AppKit

/// A full-screen, transparent, click-through window that sits above all other windows.
/// One instance is created per physical display. The CursorView lives inside this window.
final class CursorOverlayWindow: NSWindow {

    init(screen: NSScreen) {
        // Use screen.frame (full physical pixels including menu bar area),
        // NOT screen.visibleFrame which excludes the Dock and menu bar.
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        // Fully transparent background — the window itself is invisible;
        // only the CALayers drawn by CursorView are ever visible.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        alphaValue = 1  // keep at 1 so content layers render, but bg is .clear

        // Sit at the cursor window level — the same tier the hardware cursor
        // occupies, which is Int32.max. Nothing in macOS renders above this:
        // not system alerts, not Spotlight, not the screen saver.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))

        // All mouse events fall through to whatever window is underneath.
        ignoresMouseEvents = true

        // Prevent any activation path — this window must never steal focus,
        // appear in the window list, or show as "frontmost" to other apps.
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false

        // Don't show in screenshots or screen recordings taken by other apps.
        sharingType = .none

        // Appear on every Space, don't animate with Mission Control, work in full-screen.
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
    }

    // Guarantee this window can never become the key or main window,
    // regardless of how the system tries to assign it.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
