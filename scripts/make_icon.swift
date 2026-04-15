#!/usr/bin/swift
/// Generates AppIcon.iconset/<name>.png files for all required macOS icon sizes.
/// Usage:  swift scripts/make_icon.swift [output-iconset-dir]
/// Then:   iconutil -c icns <output-iconset-dir> -o AppIcon.icns

import AppKit

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon.iconset"

try! FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true)

// ── Renderer ─────────────────────────────────────────────────────────────────

func render(pixelSize px: Int) -> Data {
    let s = CGFloat(px)

    // Use NSBitmapImageRep so we get exactly px×px pixels regardless of display scale.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return Data() }

    // ── Rounded-rect clip ────────────────────────────────────────────────────
    let radius = s * 0.22
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: radius, cornerHeight: radius)
    ctx.addPath(bgPath); ctx.clip()

    // ── Indigo → purple gradient background ──────────────────────────────────
    let cs     = CGColorSpaceCreateDeviceRGB()
    let gColors = [CGColor(red: 0.09, green: 0.05, blue: 0.30, alpha: 1),
                   CGColor(red: 0.44, green: 0.16, blue: 0.78, alpha: 1)] as CFArray
    let gLocs: [CGFloat] = [0, 1]
    let grad   = CGGradient(colorsSpace: cs, colors: gColors, locations: gLocs)!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])

    // ── Cursor arrow ─────────────────────────────────────────────────────────
    // Coordinates are in NSImage/CoreGraphics Y-up space (0 = bottom).
    // The arrow tip sits at upper-left; the tail extends right and slightly down.
    let tip = CGPoint(x: s * 0.20, y: s * 0.78)

    // 7-point cursor polygon (classic Mac arrow + finger-tail)
    let pts: [CGPoint] = [
        tip,                                               // 1 tip
        CGPoint(x: s*0.20, y: s*0.26),                    // 2 shaft bottom-left
        CGPoint(x: s*0.37, y: s*0.43),                    // 3 inner notch
        CGPoint(x: s*0.51, y: s*0.25),                    // 4 tail lower-left
        CGPoint(x: s*0.63, y: s*0.37),                    // 5 tail lower-right
        CGPoint(x: s*0.49, y: s*0.53),                    // 6 tail upper-right
        CGPoint(x: s*0.33, y: s*0.65),                    // 7 shaft right
    ]

    let arrowPath = CGMutablePath()
    arrowPath.move(to: pts[0])
    pts.dropFirst().forEach { arrowPath.addLine(to: $0) }
    arrowPath.closeSubpath()

    // Draw drop-shadow first
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: s*0.012, height: -s*0.014),
                  blur: s * 0.030,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(arrowPath); ctx.fillPath()
    ctx.restoreGState()

    // White arrow body
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(arrowPath); ctx.fillPath()

    // ── Click-ripple rings centred on the arrow tip ───────────────────────────
    for (radius, alpha): (CGFloat, CGFloat) in [(s*0.13, 0.55), (s*0.22, 0.28)] {
        let ring = CGPath(ellipseIn: CGRect(
            x: tip.x - radius, y: tip.y - radius,
            width: radius * 2, height: radius * 2), transform: nil)
        ctx.addPath(ring)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.setLineWidth(s * 0.018)
        ctx.strokePath()
    }

    return rep.representation(using: .png, properties: [:])!
}

// ── Icon size table ───────────────────────────────────────────────────────────

let specs: [(pixels: Int, name: String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

for (px, name) in specs {
    let path = "\(iconsetDir)/\(name).png"
    try! render(pixelSize: px).write(to: URL(fileURLWithPath: path))
    print("  \(name).png")
}
print("Done — run: iconutil -c icns \(iconsetDir)")
