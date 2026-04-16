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
    var displayScale: CGFloat = 2.0 {
        didSet { rebuildLayers() }
    }

    /// Whether to animate the cursor shrink/spring on click.
    var showClickSwell: Bool = true

    /// Whether to show the expanding ripple ring on mouse-down.
    var showRipple: Bool = true

    /// Optional tint colour blended over the cursor image (multiply blend mode).
    /// Set to nil for no tint.
    var tintColor: NSColor? = nil {
        didSet { rebuildLayers() }
    }

    /// Animation speed multiplier. 1.0 = default. Higher = faster.
    var animationSpeed: Double = 1.0

    /// Replace the displayed cursor shape (arrow → i-beam → pointer, etc.).
    func updateCursor(_ cursor: NSCursor) {
        guard cursor.image.size != currentCursor.image.size ||
              cursor.hotSpot    != currentCursor.hotSpot    else { return }
        currentCursor = cursor
        rebuildLayers()
    }

    // MARK: - Layers

    private let cursorLayer = CALayer()
    private let rippleLayer = CALayer()

    // Extra space around the hot-spot for the ripple and spring overshoot.
    private let tipPadding: CGFloat = 24

    private var currentCursor: NSCursor = .arrow

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        isAccessibilityElement = false
        setupStaticLayers()
        rebuildLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layer construction

    private var systemCursor: NSCursor { currentCursor }

    private var scaledSize: CGSize {
        let s = systemCursor.image.size
        return CGSize(width: s.width * displayScale, height: s.height * displayScale)
    }

    private var scaledHotSpot: CGPoint {
        let h = systemCursor.hotSpot
        return CGPoint(x: h.x * displayScale, y: h.y * displayScale)
    }

    /// Runs once from init(). Sets fixed layer properties and inserts both
    /// layers into the hierarchy — they are never removed or re-added.
    private func setupStaticLayers() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        // ── Cursor layer ──────────────────────────────────────────────────
        cursorLayer.masksToBounds = false
        cursorLayer.shadowColor   = NSColor.black.cgColor
        cursorLayer.shadowOpacity = 0.45
        cursorLayer.shadowRadius  = 4
        cursorLayer.shadowOffset  = CGSize(width: 1, height: -1)
        // Cache the cursor image as a GPU bitmap. Only the transform animates,
        // which is a cheap compositing op on the cached bitmap — avoids
        // re-rendering the image on every frame.
        cursorLayer.shouldRasterize    = true
        cursorLayer.rasterizationScale = scale

        // ── Ripple layer ──────────────────────────────────────────────────
        rippleLayer.anchorPoint     = CGPoint(x: 0.5, y: 0.5)
        rippleLayer.backgroundColor = CGColor.clear
        rippleLayer.borderColor     = NSColor.white.withAlphaComponent(0.75).cgColor
        rippleLayer.borderWidth     = 2
        rippleLayer.opacity         = 0
        rippleLayer.masksToBounds   = false

        layer?.addSublayer(rippleLayer)
        layer?.addSublayer(cursorLayer)
    }

    /// Updates only the dynamic geometry and content. Never adds or removes
    /// sublayers — that only happens in setupStaticLayers().
    private func rebuildLayers() {
        let ss  = scaledSize
        let shs = scaledHotSpot

        let viewW = tipPadding + max(ss.width  - shs.x, shs.x) * 2 + tipPadding
        let viewH = tipPadding + max(ss.height - shs.y, shs.y) * 2 + tipPadding
        frame.size = CGSize(width: max(viewW, 80), height: max(viewH, 80))

        let hotInView = CGPoint(x: tipPadding, y: frame.height - tipPadding)

        let anchorX = ss.width  > 0 ? shs.x / ss.width  : 0
        let anchorY = ss.height > 0 ? 1.0 - shs.y / ss.height : 1.0

        // Suppress implicit CA animations while updating geometry/content.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        cursorLayer.bounds      = CGRect(origin: .zero, size: ss)
        cursorLayer.anchorPoint = CGPoint(x: anchorX, y: anchorY)
        cursorLayer.position    = hotInView

        cursorLayer.contents      = tintedCursorImage(size: ss)
        cursorLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        let rippleD: CGFloat = max(ss.width, ss.height) * 0.65
        rippleLayer.bounds       = CGRect(x: 0, y: 0, width: rippleD, height: rippleD)
        rippleLayer.position     = hotInView
        rippleLayer.cornerRadius = rippleD / 2

        CATransaction.commit()
    }

    // MARK: - Tint rendering

    /// Renders the cursor image, optionally blending tintColor on top using
    /// multiply compositing so the cursor silhouette is preserved.
    private func tintedCursorImage(size: CGSize) -> CGImage? {
        let src = systemCursor.image
        var proposedRect = CGRect(origin: .zero, size: size)
        guard let base = src.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { return nil }
        guard let tint = tintColor else { return base }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px    = Int(size.width * scale)
        let py    = Int(size.height * scale)
        guard px > 0, py > 0 else { return base }

        let cs  = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: py,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        ctx.scaleBy(x: scale, y: scale)

        // Draw original cursor
        ctx.draw(base, in: CGRect(origin: .zero, size: size))

        // Multiply the tint — preserves alpha, darkens toward tint hue
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(tint.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // Restore alpha that multiply blend may have clipped on transparent pixels
        ctx.setBlendMode(.destinationIn)
        ctx.draw(base, in: CGRect(origin: .zero, size: size))

        return ctx.makeImage()
    }

    // MARK: - Animations

    func animateMouseDown() {
        if showClickSwell {
            let fromScale = cursorLayer.presentation()?
                .value(forKeyPath: "transform.scale") as? CGFloat ?? 1.0

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.setValue(0.6, forKeyPath: "transform.scale")
            CATransaction.commit()

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue      = fromScale
            shrink.toValue        = 0.6
            shrink.duration       = 0.12 / max(animationSpeed, 0.01)
            shrink.timingFunction = CAMediaTimingFunction(name: .easeOut)
            cursorLayer.add(shrink, forKey: "shrink")
        }

        guard showRipple else { return }

        let expandScale       = CABasicAnimation(keyPath: "transform.scale")
        expandScale.fromValue = 1.0
        expandScale.toValue   = 2.6

        let fade              = CABasicAnimation(keyPath: "opacity")
        fade.fromValue        = 0.75
        fade.toValue          = 0.0

        let group             = CAAnimationGroup()
        group.animations      = [expandScale, fade]
        group.duration        = 0.40 / max(animationSpeed, 0.01)
        group.timingFunction  = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(group, forKey: "ripple")
    }

    func animateMouseUp() {
        guard showClickSwell else { return }

        let fromScale = cursorLayer.presentation()?
            .value(forKeyPath: "transform.scale") as? CGFloat ?? 0.6

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.setValue(1.0, forKeyPath: "transform.scale")
        CATransaction.commit()

        let spring             = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue       = fromScale
        spring.toValue         = 1.0
        spring.mass            = 1.0
        spring.stiffness       = 280 * max(animationSpeed, 0.01)
        spring.damping         = 18
        spring.initialVelocity = 0
        spring.duration        = spring.settlingDuration
        cursorLayer.add(spring, forKey: "springBack")
    }

    // MARK: - Positioning

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
