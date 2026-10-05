// Generates AppIcon.icns for TradeSync: two ascending chevrons in brushed
// silver on a machined navy tile. Mirrors BrandMark in the app.
import AppKit

func drawIcon(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    // macOS icons sit inside a margin within their canvas.
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.235
    let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Tile: navy → ink, lit from the top-left.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.231, green: 0.278, blue: 0.384, alpha: 1).cgColor, // 3B4762
        NSColor(srgbRed: 0.133, green: 0.157, blue: 0.220, alpha: 1).cgColor, // 222838
        NSColor(srgbRed: 0.067, green: 0.075, blue: 0.094, alpha: 1).cgColor  // 111318
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

    // Soft sheen across the upper third.
    let sheen = [NSColor.white.withAlphaComponent(0.10).cgColor,
                 NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray
    let sheenGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sheen, locations: [0, 1])!
    ctx.drawLinearGradient(sheenGrad,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY),
                           options: [])
    ctx.restoreGState()

    // Hairline rim.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.setLineWidth(max(0.5, s * 0.006))
    ctx.strokePath()
    ctx.restoreGState()

    // Two ascending chevrons (y grows upward in this context).
    func chevron(centerY: CGFloat, alpha: CGFloat) {
        let w = rect.width * 0.46
        let h = rect.height * 0.19
        let cx = rect.midX
        ctx.saveGState()
        ctx.setLineWidth(rect.width * 0.085)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: alpha).cgColor)
        ctx.move(to: CGPoint(x: cx - w / 2, y: centerY - h / 2))
        ctx.addLine(to: CGPoint(x: cx, y: centerY + h / 2))
        ctx.addLine(to: CGPoint(x: cx + w / 2, y: centerY - h / 2))
        ctx.strokePath()
        ctx.restoreGState()
    }
    chevron(centerY: rect.midY + rect.height * 0.105, alpha: 1.0)
    chevron(centerY: rect.midY - rect.height * 0.115, alpha: 0.42)

    img.unlockFocus()
    return img
}

func savePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
let master = drawIcon(size: 1024)
for (name, px) in sizes {
    savePNG(master, to: outDir.appendingPathComponent(name), pixels: px)
}
print("iconset written to \(outDir.path)")
