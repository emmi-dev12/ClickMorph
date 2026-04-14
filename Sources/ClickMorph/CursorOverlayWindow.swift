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

        // Fully transparent background
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // Float above normal app windows. .screenSaver (level 2000) is above
        // all regular content but below system alerts and notifications.
        level = .screenSaver

        // All mouse events fall through to whatever window is underneath.
        ignoresMouseEvents = true

        // Don't show in screenshots taken by other apps.
        // Set to .readOnly if you want the custom cursor visible in screen recordings.
        sharingType = .none

        // Exclude from Cmd+` window cycling
        isExcludedFromWindowsMenu = true

        // Appear on every Space, don't animate with Mission Control, work in full-screen
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
    }
}
