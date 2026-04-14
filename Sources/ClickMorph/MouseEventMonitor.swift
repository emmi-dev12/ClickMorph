import AppKit
import CoreGraphics
import ApplicationServices

/// Wraps a CGEventTap that listens (never filters) for mouse events system-wide.
///
/// Uses `.cghidEventTap` at the HID level so events are seen even inside
/// full-screen apps. `.listenOnly` means only Accessibility permission is
/// required — no entitlements, no root.
///
/// The CGEventTap requires a plain C callback. `self` is passed as `userInfo`
/// and recovered inside the static callback via `Unmanaged`.
final class MouseEventMonitor {

    var onMouseMove:  ((CGPoint) -> Void)?
    var onMouseDown:  ((CGPoint) -> Void)?
    var onMouseUp:    ((CGPoint) -> Void)?
    var onRightDown:  ((CGPoint) -> Void)?
    var onRightUp:    ((CGPoint) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: DispatchSourceTimer?

    // MARK: - Start / Stop

    func start() {
        guard checkAccessibilityPermission() else {
            requestAccessibilityPermission()
            pollForPermission()
            return
        }
        installTap()
    }

    func stop() {
        permissionTimer?.cancel()
        permissionTimer = nil
        removeTap()
    }

    // MARK: - CGEventTap install / remove

    private func installTap() {
        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)        |
            (1 << CGEventType.leftMouseDown.rawValue)     |
            (1 << CGEventType.leftMouseUp.rawValue)       |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.rightMouseDown.rawValue)    |
            (1 << CGEventType.rightMouseUp.rawValue)      |
            (1 << CGEventType.rightMouseDragged.rawValue)

        // Pass `self` as the userInfo pointer. Use passUnretained — the
        // CursorOverlayManager owns both the monitor and the tap lifetime,
        // so self is guaranteed to outlive the tap.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: MouseEventMonitor.tapCallback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            // tapCreate returns nil if Accessibility is still not granted.
            // The permission poller will retry.
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - C callback (must be a static/free function)

    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo = userInfo else {
            return Unmanaged.passRetained(event)
        }
        let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.dispatch(type: type, event: event)
        // passUnretained: we do not take ownership; CoreGraphics owns the event lifetime.
        // passRetained would over-retain and leak on every mouse event.
        return Unmanaged.passUnretained(event)
    }

    private func dispatch(type: CGEventType, event: CGEvent) {
        // Re-enable the tap if macOS silently disabled it (timeout or permission revoke)
        let disabledByTimeout = CGEventType(rawValue: UInt32(kCGEventTapDisabledByTimeout))
        let disabledByUser    = CGEventType(rawValue: UInt32(kCGEventTapDisabledByUserInput))
        if type == disabledByTimeout || type == disabledByUser {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let location = event.location  // CGPoint in global CG coords (origin = top-left of primary screen, Y down)

        // Dispatch to main thread — never do heavy work inside the tap callback
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
                self.onMouseMove?(location)
            case .leftMouseDown:
                self.onMouseDown?(location)
            case .leftMouseUp:
                self.onMouseUp?(location)
            case .rightMouseDown:
                self.onRightDown?(location)
            case .rightMouseUp:
                self.onRightUp?(location)
            default:
                break
            }
        }
    }

    // MARK: - Accessibility permission

    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibilityPermission() {
        // This triggers the system prompt dialog (macOS 14+: may require manual navigation)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                ClickMorph needs Accessibility access to track mouse events system-wide.

                Please enable it in:
                System Settings › Privacy & Security › Accessibility

                ClickMorph will start automatically once access is granted.
                """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .warning

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Polls every 2 seconds until Accessibility is granted, then installs the tap.
    private func pollForPermission() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.checkAccessibilityPermission() {
                self.permissionTimer?.cancel()
                self.permissionTimer = nil
                self.installTap()
            }
        }
        timer.resume()
        permissionTimer = timer
    }
}
