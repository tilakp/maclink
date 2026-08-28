// One-off icon generator: draws a modern, minimal AppIcon (teal squircle +
// white "link" glyph, matching maclink's product identity) and produces a
// full .iconset + .icns. Run with: swift Scripts/generate-icon.swift
import AppKit

let outDir = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Squircle-ish rounded background, approximating Apple's icon corner
    // radius proportion (~22.5% of the edge).
    let radius = size * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    let colors = [
        NSColor(calibratedRed: 0.063, green: 0.416, blue: 0.376, alpha: 1).cgColor, // deep teal
        NSColor(calibratedRed: 0.114, green: 0.616, blue: 0.541, alpha: 1).cgColor  // lighter teal
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Centered white "link" glyph, sized with generous padding so it reads
    // clearly at 16x16 as well as 1024x1024.
    let symbolPointSize = size * 0.52
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("SF Symbol 'link' unavailable")
    }
    let symbolSize = symbol.size
    let symbolRect = CGRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    return image
}

func savePNG(_ image: NSImage, to url: URL, size: CGFloat) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let specs: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for spec in specs {
    let image = drawIcon(size: spec.size)
    savePNG(image, to: outDir.appendingPathComponent("\(spec.name).png"), size: spec.size)
    print("wrote \(spec.name).png")
}
