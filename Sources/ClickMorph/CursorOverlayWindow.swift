import AppKit

/// A full-screen, transparent, click-through window that sits above all other windows.
/// One instance is created per physical display. The CursorView lives inside this window.
final class CursorOverlayWindow: NSWindow {

    init(screen: NSScreen) {
        // contentRect is screen.frame in global coordinates, so AppKit places
        // the window on the correct display without needing the screen: parameter.
        // (The screen: overload is a convenience init; Swift subclasses must call
        // a designated init, which is the four-argument form below.)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
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

        // Hide from the accessibility hierarchy so AX clients (automation tools,
        // remote-access apps, screen readers) see through this window to the real
        // UI underneath — the same way ignoresMouseEvents passes through hardware
        // events, isAccessibilityElement = false passes through AX hit-tests.
        isAccessibilityElement = false

        // Allow screen recording apps to capture this window so the animated
        // cursor is visible in recordings (replaces tools like Focusee).
        // .readOnly lets recorders read the pixels; they cannot write to it.
        sharingType = .readOnly

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

    // Return nil so the AX system finds no element here and falls through
    // to the window stack below — mirrors the ignoresMouseEvents pass-through
    // but for the accessibility layer.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { nil }
}
