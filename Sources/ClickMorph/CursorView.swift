import AppKit
import QuartzCore

/// The visual cursor rendered on the overlay window.
///
/// Layout: a fixed 60×60 pt transparent container view. Inside it:
///   - `rippleLayer`: an expanding ring that plays on mouseDown
///   - `cursorLayer`: a filled circle that shrinks on mouseDown and springs back on mouseUp
///
/// The entire view is repositioned on every mouse-move event to track the cursor.
/// Animations on the position change are disabled so tracking is instant.
final class CursorView: NSView {

    // MARK: - Configuration

    var cursorDiameter: CGFloat = 28 {
        didSet { reconfigureLayers() }
    }

    var cursorNSColor: NSColor = .white {
        didSet { reconfigureLayers() }
    }

    // MARK: - Layers

    private var cursorLayer = CALayer()
    private var rippleLayer = CALayer()

    // MARK: - Init

    init() {
        // Fixed 60×60 pt frame gives ~16 pt of padding all around for shadow + ripple
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layer setup

    private func setupLayers() {
        let center = CGPoint(x: 30, y: 30)

        // Ripple ring — starts fully transparent, animated only on click
        rippleLayer.bounds = CGRect(x: 0, y: 0, width: cursorDiameter, height: cursorDiameter)
        rippleLayer.position = center
        rippleLayer.cornerRadius = cursorDiameter / 2
        rippleLayer.backgroundColor = CGColor.clear
        rippleLayer.borderColor = cursorNSColor.withAlphaComponent(0.65).cgColor
        rippleLayer.borderWidth = 2
        rippleLayer.opacity = 0
        rippleLayer.masksToBounds = false

        // Cursor dot — filled circle with a soft drop shadow
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: cursorDiameter, height: cursorDiameter)
        cursorLayer.position = center
        cursorLayer.cornerRadius = cursorDiameter / 2
        cursorLayer.backgroundColor = cursorNSColor.cgColor
        cursorLayer.shadowColor = NSColor.black.cgColor
        cursorLayer.shadowOpacity = 0.45
        cursorLayer.shadowRadius = 5
        cursorLayer.shadowOffset = CGSize(width: 0, height: -2)
        cursorLayer.masksToBounds = false

        layer?.addSublayer(rippleLayer)
        layer?.addSublayer(cursorLayer)
    }

    private func reconfigureLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: cursorDiameter, height: cursorDiameter)
        cursorLayer.cornerRadius = cursorDiameter / 2
        cursorLayer.backgroundColor = cursorNSColor.cgColor
        rippleLayer.bounds = CGRect(x: 0, y: 0, width: cursorDiameter, height: cursorDiameter)
        rippleLayer.cornerRadius = cursorDiameter / 2
        rippleLayer.borderColor = cursorNSColor.withAlphaComponent(0.65).cgColor
        CATransaction.commit()
    }

    // MARK: - Animations

    func animateMouseDown() {
        // Shrink the dot to 60%
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.6
        shrink.duration = 0.12
        shrink.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        cursorLayer.add(shrink, forKey: "shrink")
        cursorLayer.setValue(0.6, forKeyPath: "transform.scale")

        // Ripple: ring expands and fades out
        let rippleScale = CABasicAnimation(keyPath: "transform.scale")
        rippleScale.fromValue = 1.0
        rippleScale.toValue = 2.4
        rippleScale.duration = 0.38

        let rippleFade = CABasicAnimation(keyPath: "opacity")
        rippleFade.fromValue = 0.7
        rippleFade.toValue = 0.0
        rippleFade.duration = 0.38

        let rippleGroup = CAAnimationGroup()
        rippleGroup.animations = [rippleScale, rippleFade]
        rippleGroup.duration = 0.38
        rippleGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rippleGroup.isRemovedOnCompletion = true
        rippleLayer.add(rippleGroup, forKey: "ripple")
    }

    func animateMouseUp() {
        // Spring back to full size with a natural overshoot
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = cursorLayer.presentation()?.value(forKeyPath: "transform.scale") ?? 0.6
        spring.toValue = 1.0
        spring.mass = 1.0
        spring.stiffness = 280
        spring.damping = 18
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        spring.isRemovedOnCompletion = true
        cursorLayer.add(spring, forKey: "springBack")
        cursorLayer.setValue(1.0, forKeyPath: "transform.scale")
    }

    // MARK: - Positioning

    /// Move the view so its center sits at `windowPoint` (in window coordinates).
    /// Wrapped in a disabled-actions CATransaction so movement is instant — no lag.
    func moveCenter(to windowPoint: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.origin = CGPoint(
            x: windowPoint.x - frame.width / 2,
            y: windowPoint.y - frame.height / 2
        )
        CATransaction.commit()
    }
}
