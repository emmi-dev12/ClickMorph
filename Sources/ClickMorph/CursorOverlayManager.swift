import AppKit
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

    // Reference-counted cursor hiding — NSCursor.hide() is cumulative
    private var cursorHideDepth = 0

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

    func setCursorDiameter(_ d: CGFloat) {
        cursorView.cursorDiameter = d
    }

    func setCursorColor(_ color: NSColor) {
        cursorView.cursorNSColor = color
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
        cursorView.moveCenter(to: windowPoint)
    }

    // MARK: - Cursor hiding (reference-counted)

    private func hideCursor() {
        if cursorHideDepth == 0 {
            NSCursor.hide()
            // Belt-and-suspenders: set a transparent cursor so the system
            // renders nothing even if hide() doesn't fully suppress it
            makeTransparentCursor()?.set()
        }
        cursorHideDepth += 1
    }

    private func showCursor() {
        guard cursorHideDepth > 0 else { return }
        cursorHideDepth -= 1
        if cursorHideDepth == 0 {
            NSCursor.unhide()
            NSCursor.arrow.set()
        }
    }

    private func makeTransparentCursor() -> NSCursor? {
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: .zero)
    }
}
