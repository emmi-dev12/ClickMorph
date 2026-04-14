import AppKit
import QuartzCore

/// Renders the system cursor image at a configurable scale, with a
/// click-shrink + spring-back animation and an optional outward ripple ring.
///
/// Positioning is hot-spot based: `moveHotspot(to:)` places the cursor TIP
/// (not the view centre) at the given window coordinate.
final class CursorView: NSView {

    // MARK: - Configuration

    /// Multiplier applied to the system cursor's logical size.
    /// 1.0 = native size, 2.0 = 2× larger, etc.
    var displayScale: CGFloat = 2.0 {
        didSet { rebuildLayers() }
    }

    /// Whether to animate the cursor shrink/spring on click.
    var showClickSwell: Bool = true

    /// Whether to show the expanding ripple ring on mouse-down.
    var showRipple: Bool = true

    /// Replace the displayed cursor shape (arrow → i-beam → pointer, etc.).
    /// Rebuilds layers; the next moveHotspot call repositions correctly.
    func updateCursor(_ cursor: NSCursor) {
        guard cursor.image.size != currentCursor.image.size ||
              cursor.hotSpot    != currentCursor.hotSpot    else { return }
        currentCursor = cursor
        rebuildLayers()
    }

    // MARK: - Layers

    private let cursorLayer = CALayer()
    private let rippleLayer = CALayer()

    // Pixels from the view's top-left corner to the cursor hot-spot.
    // Extra breathing room for the ripple ring and the spring overshoot.
    private let tipPadding: CGFloat = 24

    // Currently rendered cursor — updated via updateCursor(_:)
    private var currentCursor: NSCursor = .arrow

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        rebuildLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layer construction

    private var systemCursor: NSCursor { currentCursor }

    /// Logical size of the cursor image at the current displayScale.
    private var scaledSize: CGSize {
        let s = systemCursor.image.size
        return CGSize(width: s.width * displayScale,
                      height: s.height * displayScale)
    }

    /// Cursor hot-spot offset from the image's top-left corner, in scaled points.
    private var scaledHotSpot: CGPoint {
        let h = systemCursor.hotSpot       // in image-space (Y down from top-left)
        return CGPoint(x: h.x * displayScale, y: h.y * displayScale)
    }

    private func rebuildLayers() {
        let ss  = scaledSize
        let shs = scaledHotSpot

        // Size the view so the cursor image fits with tipPadding on every side
        // measured from the hot-spot outward.
        let viewW = tipPadding + max(ss.width  - shs.x, shs.x) * 2 + tipPadding
        let viewH = tipPadding + max(ss.height - shs.y, shs.y) * 2 + tipPadding
        frame.size = CGSize(width: max(viewW, 80), height: max(viewH, 80))

        // Hot-spot position inside this view in AppKit coordinates (Y-up).
        // We put the hot-spot tipPadding points from the top-left corner.
        let hotInView = CGPoint(x: tipPadding,
                                y: frame.height - tipPadding)

        // ── Cursor layer ────────────────────────────────────────────────────
        // anchorPoint places the hot-spot at `position`.
        //   CA anchorPoint y=0 → visual bottom, y=1 → visual top.
        //   hot-spot is at (shs.x, shs.y) from the image's top-left (Y down).
        //   In CA normalised coords: anchorY = 1 − shs.y / ss.height
        let anchorX = ss.width  > 0 ? shs.x / ss.width  : 0
        let anchorY = ss.height > 0 ? 1.0 - shs.y / ss.height : 1.0

        cursorLayer.bounds       = CGRect(origin: .zero, size: ss)
        cursorLayer.anchorPoint  = CGPoint(x: anchorX, y: anchorY)
        cursorLayer.position     = hotInView
        cursorLayer.masksToBounds = false

        // Render the system cursor image into the layer.
        var proposedRect = CGRect(origin: .zero, size: ss)
        if let cgImg = systemCursor.image.cgImage(
            forProposedRect: &proposedRect, context: nil, hints: nil) {
            cursorLayer.contents      = cgImg
            cursorLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        }

        // Subtle drop shadow so the white arrow stays visible on light backgrounds
        cursorLayer.shadowColor   = NSColor.black.cgColor
        cursorLayer.shadowOpacity = 0.45
        cursorLayer.shadowRadius  = 4
        cursorLayer.shadowOffset  = CGSize(width: 1, height: -1)

        // ── Ripple layer ─────────────────────────────────────────────────────
        let rippleD: CGFloat = max(ss.width, ss.height) * 0.65
        rippleLayer.bounds          = CGRect(x: 0, y: 0, width: rippleD, height: rippleD)
        rippleLayer.position        = hotInView
        rippleLayer.anchorPoint     = CGPoint(x: 0.5, y: 0.5)
        rippleLayer.cornerRadius    = rippleD / 2
        rippleLayer.backgroundColor = CGColor.clear
        rippleLayer.borderColor     = NSColor.white.withAlphaComponent(0.75).cgColor
        rippleLayer.borderWidth     = 2
        rippleLayer.opacity         = 0
        rippleLayer.masksToBounds   = false

        // Rebuild sublayers from scratch
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer?.addSublayer(rippleLayer)
        layer?.addSublayer(cursorLayer)
    }

    // MARK: - Animations

    /// Press: cursor shrinks to 60 % (scaling from the hot-spot tip) and,
    /// when enabled, a ripple ring expands outward from the same point.
    func animateMouseDown() {
        if showClickSwell {
            let fromScale = cursorLayer.presentation()?
                .value(forKeyPath: "transform.scale") as? CGFloat ?? 1.0

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.setValue(0.6, forKeyPath: "transform.scale")
            CATransaction.commit()

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = fromScale
            shrink.toValue   = 0.6
            shrink.duration  = 0.12
            shrink.timingFunction = CAMediaTimingFunction(name: .easeOut)
            cursorLayer.add(shrink, forKey: "shrink")
        }

        guard showRipple else { return }

        let expandScale        = CABasicAnimation(keyPath: "transform.scale")
        expandScale.fromValue  = 1.0
        expandScale.toValue    = 2.6

        let fade               = CABasicAnimation(keyPath: "opacity")
        fade.fromValue         = 0.75
        fade.toValue           = 0.0

        let group              = CAAnimationGroup()
        group.animations       = [expandScale, fade]
        group.duration         = 0.40
        group.timingFunction   = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(group, forKey: "ripple")
    }

    /// Release: cursor springs back to full size with a natural overshoot.
    func animateMouseUp() {
        guard showClickSwell else { return }

        let fromScale = cursorLayer.presentation()?
            .value(forKeyPath: "transform.scale") as? CGFloat ?? 0.6

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.setValue(1.0, forKeyPath: "transform.scale")
        CATransaction.commit()

        let spring               = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue         = fromScale
        spring.toValue           = 1.0
        spring.mass              = 1.0
        spring.stiffness         = 280
        spring.damping           = 18
        spring.initialVelocity   = 0
        spring.duration          = spring.settlingDuration
        cursorLayer.add(spring, forKey: "springBack")
    }

    // MARK: - Positioning

    /// Move the view so its cursor tip (hot-spot) sits at `windowPoint`.
    /// Wrapped in a disabled-actions transaction so tracking is instant.
    func moveHotspot(to windowPoint: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.origin = CGPoint(
            x: windowPoint.x - tipPadding,
            y: windowPoint.y - (frame.height - tipPadding)
        )
        CATransaction.commit()
    }
}
