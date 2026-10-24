import AppKit

let output = CommandLine.arguments[1]
let folder = URL(fileURLWithPath: output).appendingPathComponent("Encore.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let background = NSBezierPath(roundedRect: NSRect(x: p * 0.055, y: p * 0.055, width: p * 0.89, height: p * 0.89), xRadius: p * 0.21, yRadius: p * 0.21)
        NSGradient(starting: NSColor(red: 0.24, green: 0.17, blue: 0.38, alpha: 1), ending: NSColor(red: 0.1, green: 0.08, blue: 0.16, alpha: 1))!.draw(in: background, angle: -70)
        NSGraphicsContext.saveGraphicsState()
        let rotated = NSAffineTransform()
        rotated.translateX(by: p * 0.43, yBy: p * 0.53)
        rotated.rotate(byDegrees: 15)
        rotated.concat()
        let card = NSBezierPath(roundedRect: NSRect(x: -p * 0.24, y: -p * 0.28, width: p * 0.48, height: p * 0.56), xRadius: p * 0.085, yRadius: p * 0.085)
        NSColor(red: 0.52, green: 0.37, blue: 0.8, alpha: 1).setFill(); card.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        let front = NSAffineTransform()
        front.translateX(by: p * 0.57, yBy: p * 0.47)
        front.rotate(byDegrees: -8); front.concat()
        NSGradient(starting: NSColor(red: 0.8, green: 0.66, blue: 1, alpha: 1), ending: NSColor(red: 0.51, green: 0.3, blue: 0.92, alpha: 1))!.draw(in: card, angle: -70)
        if let symbol = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: p * 0.25, weight: .bold)) {
            let tinted = NSImage(size: symbol.size)
            tinted.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: symbol.size).fill()
            symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: -p * 0.15, y: -p * 0.12, width: p * 0.3, height: p * 0.24))
        }
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
