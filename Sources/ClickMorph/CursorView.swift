import AppKit
import QuartzCore

/// Represents the custom cursor shape type
enum CustomCursorShape {
    case system
    case dot
    case triangle
    case custom(imagePath: String)
}

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

    /// Custom shape type and optional image path
    var customShape: CustomCursorShape = .system {
        didSet { rebuildLayers() }
    }

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
        setupStaticLayers()
        rebuildLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layer construction

    private var systemCursor: NSCursor { currentCursor }

    private var scaledSize: CGSize {
        // For custom shapes, use a standard size scaled by displayScale;
        // for system cursor, scale the image size
        let baseSize: CGSize
        switch customShape {
        case .system:
            let s = systemCursor.image.size
            baseSize = CGSize(width: s.width * displayScale, height: s.height * displayScale)
        case .dot, .triangle, .custom:
            baseSize = CGSize(width: 16 * displayScale, height: 16 * displayScale)
        }
        return baseSize
    }

    private var scaledHotSpot: CGPoint {
        // For custom shapes, center the hotspot; for system cursor, use the actual hotspot
        switch customShape {
        case .system:
            let h = systemCursor.hotSpot
            return CGPoint(x: h.x * displayScale, y: h.y * displayScale)
        case .dot, .triangle, .custom:
            let ss = scaledSize
            return CGPoint(x: ss.width / 2, y: ss.height / 2)
        }
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

        cursorLayer.contents      = cursorImage(size: ss)
        cursorLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        let rippleD: CGFloat = max(ss.width, ss.height) * 0.65
        rippleLayer.bounds       = CGRect(x: 0, y: 0, width: rippleD, height: rippleD)
        rippleLayer.position     = hotInView
        rippleLayer.cornerRadius = rippleD / 2

        CATransaction.commit()
    }

    // MARK: - Cursor image rendering

    /// Returns the appropriate cursor image based on the current shape setting
    private func cursorImage(size: CGSize) -> CGImage? {
        switch customShape {
        case .system:
            return tintedCursorImage(size: size)
        case .dot:
            return renderDotCursor(size: size)
        case .triangle:
            return renderTriangleCursor(size: size)
        case .custom(let imagePath):
            return loadCustomCursorImage(from: imagePath, size: size)
        }
    }

    /// Renders a simple dot cursor
    private func renderDotCursor(size: CGSize) -> CGImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = Int(size.width * scale)
        let py = Int(size.height * scale)
        guard px > 0, py > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: py,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)

        let dotRadius = min(size.width, size.height) * 0.25
        let dotRect = CGRect(x: size.width / 2 - dotRadius, y: size.height / 2 - dotRadius,
                             width: dotRadius * 2, height: dotRadius * 2)

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: dotRect)

        if let tint = tintColor {
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(tint.cgColor)
            ctx.fillEllipse(in: dotRect)
            ctx.setBlendMode(.destinationIn)
            ctx.fillEllipse(in: dotRect)
        }

        return ctx.makeImage()
    }

    /// Renders a triangle cursor
    private func renderTriangleCursor(size: CGSize) -> CGImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = Int(size.width * scale)
        let py = Int(size.height * scale)
        guard px > 0, py > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: py,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)

        let centerX = size.width / 2
        let centerY = size.height / 2
        let triangleSize = min(size.width, size.height) * 0.3

        ctx.beginPath()
        ctx.move(to: CGPoint(x: centerX, y: centerY - triangleSize))
        ctx.addLine(to: CGPoint(x: centerX + triangleSize, y: centerY + triangleSize))
        ctx.addLine(to: CGPoint(x: centerX - triangleSize, y: centerY + triangleSize))
        ctx.closePath()

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()

        if let tint = tintColor {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: centerX, y: centerY - triangleSize))
            ctx.addLine(to: CGPoint(x: centerX + triangleSize, y: centerY + triangleSize))
            ctx.addLine(to: CGPoint(x: centerX - triangleSize, y: centerY + triangleSize))
            ctx.closePath()
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(tint.cgColor)
            ctx.fillPath()

            ctx.beginPath()
            ctx.move(to: CGPoint(x: centerX, y: centerY - triangleSize))
            ctx.addLine(to: CGPoint(x: centerX + triangleSize, y: centerY + triangleSize))
            ctx.addLine(to: CGPoint(x: centerX - triangleSize, y: centerY + triangleSize))
            ctx.closePath()
            ctx.setBlendMode(.destinationIn)
            ctx.fillPath()
        }

        return ctx.makeImage()
    }

    /// Loads and scales a custom image as cursor
    private func loadCustomCursorImage(from path: String, size: CGSize) -> CGImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }

        let targetSize = size
        var proposedRect = CGRect(origin: .zero, size: targetSize)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { return nil }

        if let tint = tintColor {
            return applyTintToImage(cgImage, size: targetSize, tintColor: tint)
        }
        return cgImage
    }

    /// Applies tint color to a CGImage
    private func applyTintToImage(_ baseImage: CGImage, size: CGSize, tintColor: NSColor) -> CGImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = Int(size.width * scale)
        let py = Int(size.height * scale)
        guard px > 0, py > 0 else { return baseImage }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: py,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return baseImage }

        ctx.scaleBy(x: scale, y: scale)

        ctx.draw(baseImage, in: CGRect(origin: .zero, size: size))
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(tintColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setBlendMode(.destinationIn)
        ctx.draw(baseImage, in: CGRect(origin: .zero, size: size))

        return ctx.makeImage()
    }

    /// Renders the cursor image, optionally blending tintColor on top using
    /// multiply compositing so the cursor silhouette is preserved.
    private func tintedCursorImage(size: CGSize) -> CGImage? {
        let src = systemCursor.image
        var proposedRect = CGRect(origin: .zero, size: size)
        guard let base = src.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { return nil }
        guard let tint = tintColor else { return base }

        return applyTintToImage(base, size: size, tintColor: tint)
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
