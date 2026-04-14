import AppKit
import CoreGraphics
import QuartzCore

/// Central coordinator. Owns:
///   - One `CursorOverlayWindow` per physical display
///   - The single `CursorView` that moves between those windows
///   - The `MouseEventMonitor` that feeds events in
///
/// Call `start()` once on app launch. Use `enable()` / `disable()` to
/// toggle the custom cursor on and off at runtime.
final class CursorOverlayManager: NSObject {

    // MARK: - State

    private(set) var isEnabled = false

    // One overlay window per screen, keyed by the screen object
    private var overlayWindows: [NSScreen: CursorOverlayWindow] = [:]

    // The single cursor view; moved between windows as the mouse crosses displays
    private let cursorView = CursorView()

    private let monitor = MouseEventMonitor()

    // Reference-counted cursor hiding
    private var cursorHideDepth = 0
    // Display IDs we've hidden — lets us show/hide only the right displays
    private var hiddenDisplayIDs: Set<CGDirectDisplayID> = []
    // Periodically resets the CGDisplay hide counter to exactly 1 so any
    // system-initiated show calls can't permanently surface the cursor
    private var reHideTimer: DispatchSourceTimer?

    // MARK: - Public API

    /// Call once from the @main App's initialiser.
    func start() {
        buildWindows()
        wireMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Re-raise windows to the top after the display wakes from sleep or lock screen
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensAwoke),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        enable()
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        overlayWindows.values.forEach { $0.orderFront(nil) }
        hideCursor()
        monitor.start()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        overlayWindows.values.forEach { $0.orderOut(nil) }
        showCursor()
        monitor.stop()
    }

    // MARK: - Cursor appearance pass-through

    func setCursorScale(_ scale: CGFloat) {
        cursorView.displayScale = scale
    }

    // MARK: - Monitor wiring

    private func wireMonitor() {
        monitor.onMouseMove = { [weak self] point in
            self?.updateCursorPosition(point)
        }
        monitor.onMouseDown = { [weak self] point in
            self?.updateCursorPosition(point)
            self?.cursorView.animateMouseDown()
        }
        monitor.onMouseUp = { [weak self] point in
            self?.updateCursorPosition(point)
            self?.cursorView.animateMouseUp()
        }
        // Right-click gets the same animation
        monitor.onRightDown = { [weak self] point in
            self?.updateCursorPosition(point)
            self?.cursorView.animateMouseDown()
        }
        monitor.onRightUp = { [weak self] point in
            self?.updateCursorPosition(point)
            self?.cursorView.animateMouseUp()
        }
    }

    // MARK: - Window management

    private func buildWindows() {
        for screen in NSScreen.screens {
            let window = CursorOverlayWindow(screen: screen)
            overlayWindows[screen] = window
        }
        // Add cursorView to a window so it exists in the view hierarchy
        if let firstWindow = overlayWindows.values.first {
            firstWindow.contentView?.addSubview(cursorView)
        }
    }

    private func teardownWindows() {
        cursorView.removeFromSuperview()
        overlayWindows.values.forEach { $0.close() }
        overlayWindows.removeAll()
    }

    @objc private func screensChanged() {
        teardownWindows()
        buildWindows()
        if isEnabled {
            overlayWindows.values.forEach { $0.orderFront(nil) }
            // A newly connected display was never passed to CGDisplayHideCursor.
            // Hide only the new IDs to avoid incrementing the hide-depth counter
            // on displays that are already hidden.
            let current = Set(activeDisplayIDs())
            current.subtracting(hiddenDisplayIDs).forEach { CGDisplayHideCursor($0) }
            hiddenDisplayIDs = current
        }
    }

    @objc private func screensAwoke() {
        if isEnabled {
            overlayWindows.values.forEach { $0.orderFront(nil) }
            // The display server resets cursor state on wake; re-hide immediately
            reapplyCursorHide()
        }
    }

    // MARK: - Cursor position

    private func updateCursorPosition(_ cgGlobalPoint: CGPoint) {
        // Convert from CG coords (origin top-left, Y down) to AppKit coords (origin bottom-left, Y up)
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let nsGlobalPoint = NSPoint(x: cgGlobalPoint.x, y: primaryHeight - cgGlobalPoint.y)

        // Find which screen contains the cursor
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(nsGlobalPoint) }) else { return }
        guard let targetWindow = overlayWindows[targetScreen] else { return }

        // If the view is on a different window, move it
        if cursorView.window !== targetWindow {
            cursorView.removeFromSuperview()
            targetWindow.contentView?.addSubview(cursorView)
        }

        // Convert global AppKit point → window-local point → view coordinate
        let windowPoint = targetWindow.convertPoint(fromScreen: nsGlobalPoint)
        cursorView.moveHotspot(to: windowPoint)
    }

    // MARK: - Cursor hiding

    private func hideCursor() {
        if cursorHideDepth == 0 {
            // NSCursor.hide() is Apple's recommended replacement for the deprecated
            // CGDisplayHideCursor. On macOS 14+ it operates at the window-server level.
            NSCursor.hide()
            reapplyCursorHide()
            startReHideTimer()
        }
        cursorHideDepth += 1
    }

    private func showCursor() {
        guard cursorHideDepth > 0 else { return }
        cursorHideDepth -= 1
        if cursorHideDepth == 0 {
            stopReHideTimer()
            NSCursor.unhide()
            hiddenDisplayIDs.forEach { CGDisplayShowCursor($0) }
            hiddenDisplayIDs = []
        }
    }

    /// Resets the CGDisplay hide counter to exactly 1 on every active display.
    /// Calling show → hide in the same synchronous block is atomic from the
    /// compositor's perspective — no frame is rendered between the two calls.
    private func reapplyCursorHide() {
        hiddenDisplayIDs.forEach { CGDisplayShowCursor($0) }
        let ids = activeDisplayIDs()
        ids.forEach { CGDisplayHideCursor($0) }
        hiddenDisplayIDs = Set(ids)
    }

    /// Fires every 2 s to recover from any system-side CGDisplayShowCursor call
    /// that might have decremented our hide counter to 0.
    private func startReHideTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.reapplyCursorHide()
        }
        timer.resume()
        reHideTimer = timer
    }

    private func stopReHideTimer() {
        reHideTimer?.cancel()
        reHideTimer = nil
    }

    /// Returns all currently active (non-mirrored, non-sleeping) display IDs.
    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: kCGNullDirectDisplay, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids
    }
}
