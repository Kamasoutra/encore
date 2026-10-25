import AppKit

let output = CommandLine.arguments[1]
let folder = URL(fileURLWithPath: output).appendingPathComponent("Encore.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

func shadow(_ p: CGFloat, y: CGFloat, blur: CGFloat, alpha: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -p * y)
    shadow.shadowBlurRadius = p * blur
    shadow.shadowColor = color(0.05, 0.02, 0.12, alpha)
    shadow.set()
}

func arrow(_ pointSize: CGFloat, weight: NSFont.Weight, tint: NSColor) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) else { return nil }
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    tint.setFill(); NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    return tinted
}

func draw(_ p: CGFloat) {
    let small = p <= 32
    // macOS grid: an 824 pt body centered in 1024, leaving room for the drop shadow.
    let rect = NSRect(x: p * 0.0977, y: p * 0.0977, width: p * 0.8047, height: p * 0.8047)
    let body = NSBezierPath(roundedRect: rect, xRadius: p * 0.18, yRadius: p * 0.18)
    NSGraphicsContext.saveGraphicsState()
    shadow(p, y: 0.012, blur: 0.03, alpha: 0.45)
    color(0.17, 0.12, 0.28).setFill(); body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.29, 0.2, 0.46), color(0.16, 0.11, 0.27), color(0.09, 0.07, 0.15)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: body, angle: -90)
    // Soft violet glow behind the cards.
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(starting: color(0.62, 0.42, 1, 0.38), ending: color(0.62, 0.42, 1, 0))!.draw(fromCenter: NSPoint(x: p * 0.52, y: p * 0.52), radius: 0, toCenter: NSPoint(x: p * 0.52, y: p * 0.52), radius: p * 0.42, options: [])
    NSGraphicsContext.restoreGraphicsState()
    if !small {
        let rim = NSBezierPath(roundedRect: rect.insetBy(dx: p * 0.002, dy: p * 0.002), xRadius: p * 0.178, yRadius: p * 0.178)
        rim.lineWidth = p * 0.004
        color(1, 1, 1, 0.14).setStroke(); rim.stroke()
    }

    let card = NSBezierPath(roundedRect: NSRect(x: -p * 0.2, y: -p * 0.24, width: p * 0.4, height: p * 0.48), xRadius: p * 0.07, yRadius: p * 0.07)
    NSGraphicsContext.saveGraphicsState()
    let back = NSAffineTransform()
    back.translateX(by: p * 0.43, yBy: p * 0.53)
    back.rotate(byDegrees: 14)
    back.concat()
    shadow(p, y: 0.01, blur: 0.025, alpha: 0.35)
    color(0.45, 0.31, 0.74).setFill(); card.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let front = NSAffineTransform()
    front.translateX(by: p * 0.565, yBy: p * 0.465)
    front.rotate(byDegrees: -7)
    front.concat()
    NSGraphicsContext.saveGraphicsState()
    shadow(p, y: 0.022, blur: 0.05, alpha: 0.55)
    color(0.51, 0.3, 0.92).setFill(); card.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.84, 0.72, 1), ending: color(0.52, 0.31, 0.93))!.draw(in: card, angle: -80)
    if !small {
        // Thin highlight along the top edge of the front card.
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        NSGradient(starting: color(1, 1, 1, 0.35), ending: color(1, 1, 1, 0))!.draw(in: NSRect(x: -p * 0.2, y: p * 0.16, width: p * 0.4, height: p * 0.08), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    if let mark = arrow(p * (small ? 0.26 : 0.22), weight: small ? .heavy : .bold, tint: .white) {
        let width = p * (small ? 0.28 : 0.24)
        let size = NSSize(width: width, height: width * mark.size.height / mark.size.width)
        NSGraphicsContext.saveGraphicsState()
        if !small { shadow(p, y: 0.006, blur: 0.012, alpha: 0.3) }
        mark.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
