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

    private var overlayWindows: [NSScreen: CursorOverlayWindow] = [:]
    private let cursorView = CursorView()
    private let monitor = MouseEventMonitor()

    // Cursor hiding state
    private var cursorHideDepth = 0
    private var hiddenDisplayIDs: Set<CGDirectDisplayID> = []
    private var reHideTimer: DispatchSourceTimer?

    // Cursor shape tracking — updated in the mouse-move handler, not a timer
    private var lastSeenCursor: NSCursor? = nil

    // 1×1 fully transparent cursor — set on every mouse event so the system
    // cursor stays invisible regardless of what other apps try to show
    private lazy var transparentCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: img.size)).fill()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: .zero)
    }()

    // MARK: - Public API

    func start() {
        buildWindows()
        wireMonitor()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensAwoke),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        enable()
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        overlayWindows.values.forEach { $0.orderFront(nil) }
        enableBackgroundCursorOps()
        hideCursor()
        monitor.start()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        lastSeenCursor = nil
        overlayWindows.values.forEach { $0.orderOut(nil) }
        showCursor()
        monitor.stop()
    }

    // MARK: - Cursor scale pass-through

    func setCursorScale(_ scale: CGFloat) {
        cursorView.displayScale = scale
    }

    // MARK: - Monitor wiring

    private func wireMonitor() {
        monitor.onMouseMove = { [weak self] point in
            guard let self else { return }
            self.updateCursorPosition(point)
            if self.isEnabled {
                // Snapshot the real cursor BEFORE we override it with transparent.
                // By the time this async block runs, the app under the cursor has
                // already processed the event (tracking area, cursor rects, etc.)
                // and called NSCursor.set() — so currentSystem reflects their choice.
                self.snapshotCursorShape()
                self.transparentCursor.set()
            }
        }
        monitor.onMouseDown = { [weak self] point in
            guard let self else { return }
            self.updateCursorPosition(point)
            self.cursorView.animateMouseDown()
            if self.isEnabled { self.transparentCursor.set() }
        }
        monitor.onMouseUp = { [weak self] point in
            guard let self else { return }
            self.updateCursorPosition(point)
            self.cursorView.animateMouseUp()
            if self.isEnabled { self.transparentCursor.set() }
        }
        monitor.onRightDown = { [weak self] point in
            guard let self else { return }
            self.updateCursorPosition(point)
            self.cursorView.animateMouseDown()
            if self.isEnabled { self.transparentCursor.set() }
        }
        monitor.onRightUp = { [weak self] point in
            guard let self else { return }
            self.updateCursorPosition(point)
            self.cursorView.animateMouseUp()
            if self.isEnabled { self.transparentCursor.set() }
        }
    }

    // MARK: - Window management

    private func buildWindows() {
        for screen in NSScreen.screens {
            overlayWindows[screen] = CursorOverlayWindow(screen: screen)
        }
        if let first = overlayWindows.values.first {
            first.contentView?.addSubview(cursorView)
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
            let current = Set(activeDisplayIDs())
            current.subtracting(hiddenDisplayIDs).forEach { CGDisplayHideCursor($0) }
            hiddenDisplayIDs = current
        }
    }

    @objc private func screensAwoke() {
        if isEnabled {
            overlayWindows.values.forEach { $0.orderFront(nil) }
            reapplyCursorHide()
        }
    }

    // MARK: - Cursor position

    private func updateCursorPosition(_ cgPoint: CGPoint) {
        guard let primaryH = NSScreen.screens.first?.frame.height else { return }
        let nsPoint = NSPoint(x: cgPoint.x, y: primaryH - cgPoint.y)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(nsPoint) }),
              let window = overlayWindows[screen] else { return }
        if cursorView.window !== window {
            cursorView.removeFromSuperview()
            window.contentView?.addSubview(cursorView)
        }
        cursorView.moveHotspot(to: window.convertPoint(fromScreen: nsPoint))
    }

    // MARK: - Cursor shape tracking

    /// Called from the mouse-move handler immediately before transparentCursor.set().
    /// Reads NSCursor.currentSystem while it still reflects the real cursor that the
    /// app under the cursor set; ignores our own 1×1 transparent cursor.
    private func snapshotCursorShape() {
        guard let cursor = NSCursor.currentSystem,
              cursor.image.size.width > 2 else { return }   // skip our 1×1 transparent cursor
        // Structural equality: same image size + same hot-spot = same visual shape.
        if cursor.image.size != lastSeenCursor?.image.size ||
           cursor.hotSpot    != lastSeenCursor?.hotSpot {
            lastSeenCursor = cursor
            cursorView.updateCursor(cursor)
        }
    }

    // MARK: - Cursor hiding

    /// Tells the window server that this connection may set the cursor even
    /// when it is not the frontmost application.
    /// Uses private CoreGraphics SPI via dlsym so the app fails gracefully
    /// if the symbol is ever removed rather than crashing at link time.
    private func enableBackgroundCursorOps() {
        typealias GetConn  = @convention(c) () -> UInt32
        typealias SetProp  = @convention(c) (UInt32, UInt32, CFString, CFTypeRef) -> Int32
        // RTLD_DEFAULT is (void*)-2 — Swift can't import the C pointer-cast macro directly.
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let rawGet  = dlsym(rtldDefault, "CGSMainConnectionID"),
              let rawSet  = dlsym(rtldDefault, "CGSSetConnectionProperty") else { return }
        let getConn = unsafeBitCast(rawGet, to: GetConn.self)
        let setProp = unsafeBitCast(rawSet, to: SetProp.self)
        let conn = getConn()
        _ = setProp(conn, conn, "SetsCursorInBackground" as CFString,
                    kCFBooleanTrue as CFTypeRef)
    }

    private func hideCursor() {
        if cursorHideDepth == 0 {
            // Set a transparent cursor image — invisible, no counter issues
            transparentCursor.set()
            // Belt-and-suspenders: also use the legacy hide APIs
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
            NSCursor.arrow.set()
            hiddenDisplayIDs.forEach { CGDisplayShowCursor($0) }
            hiddenDisplayIDs = []
        }
    }

    /// Resets the CGDisplay hide counter to exactly 1 on every active display
    /// (show → depth 0, hide → depth 1) — the two calls are synchronous so
    /// no compositor frame renders between them.
    private func reapplyCursorHide() {
        hiddenDisplayIDs.forEach { CGDisplayShowCursor($0) }
        let ids = activeDisplayIDs()
        ids.forEach { CGDisplayHideCursor($0) }
        hiddenDisplayIDs = Set(ids)
    }

    private func startReHideTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.reapplyCursorHide()
            self?.transparentCursor.set()
        }
        timer.resume()
        reHideTimer = timer
    }

    private func stopReHideTimer() {
        reHideTimer?.cancel()
        reHideTimer = nil
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: kCGNullDirectDisplay, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids
    }
}
