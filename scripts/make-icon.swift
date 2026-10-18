// Renders the Figures "Grid F" app icon at every size the Mac and iOS apps need.
// Usage: swift scripts/make-icon.swift <output-directory>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Apple/Icon")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Apple's continuous-corner shape, approximated by a superellipse.
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let (cx, cy, rx, ry) = (rect.midX, rect.midY, rect.width / 2, rect.height / 2)
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let (c, s) = (cos(t), sin(t))
        let x = cx + rx * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / exponent)
        let y = cy + ry * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / exponent)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// Draws the icon artwork filling `body` (top-left origin).
func drawArtwork(_ ctx: CGContext, body: CGRect) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Background: a fresh green that deepens toward the bottom.
    let background = CGGradient(colorsSpace: space, colors: [color(0x3DD07E), color(0x1E9A57), color(0x10673A)] as CFArray,
                                locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: body.midX, y: body.minY),
                           end: CGPoint(x: body.midX, y: body.maxY), options: [])
    // Soft light from the top.
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: body.midX, y: body.minY - body.height * 0.1), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.minY - body.height * 0.1), endRadius: body.width * 0.85, options: [])

    // A 4 × 5 grid of cells; the white ones spell F.
    let unit = body.width / 100
    let cell = 13.2 * unit
    let gap = 3.6 * unit
    let gridWidth = 4 * cell + 3 * gap
    let gridHeight = 5 * cell + 4 * gap
    let origin = CGPoint(x: body.midX - gridWidth / 2 + 1.2 * unit, y: body.midY - gridHeight / 2)
    let lit: Set<[Int]> = [[0, 0], [0, 1], [0, 2], [0, 3], [1, 0], [2, 0], [2, 1], [2, 2], [3, 0], [4, 0]]
    let radius = cell * 0.24

    for row in 0..<5 {
        for column in 0..<4 {
            let rect = CGRect(x: origin.x + CGFloat(column) * (cell + gap), y: origin.y + CGFloat(row) * (cell + gap),
                              width: cell, height: cell)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if lit.contains([row, column]) {
                // Raised white tiles with a soft shadow and a faint cool gradient.
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 1.6 * unit), blur: 3.2 * unit, color: color(0x063A20, 0.45))
                ctx.addPath(path)
                ctx.setFillColor(color(0xFFFFFF))
                ctx.fillPath()
                ctx.restoreGState()
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                let tile = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xE3F6EA)] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(tile, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
                ctx.restoreGState()
            } else {
                // Glassy empty cells.
                ctx.addPath(path)
                ctx.setFillColor(color(0xFFFFFF, 0.17))
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(color(0xFFFFFF, 0.22))
                ctx.setLineWidth(max(0.5, 0.35 * unit))
                ctx.strokePath()
            }
        }
    }
}

/// - mac: transparent canvas, squircle body on Apple's 824/1024 grid with a drop shadow.
/// - iOS: opaque full-bleed square; the system applies its own mask.
func render(size: Int, mac: Bool) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // Work in a top-left coordinate space.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    if mac {
        let body = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
        let shape = squircle(body)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: s * 10 / 1024), blur: s * 22 / 1024, color: color(0x000000, 0.32))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x1E9A57))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        drawArtwork(ctx, body: body)
        ctx.restoreGState()
        // Fine inner edge, as on Apple's own icons.
        ctx.addPath(shape)
        ctx.setStrokeColor(color(0xFFFFFF, 0.18))
        ctx.setLineWidth(max(0.5, s / 512))
        ctx.strokePath()
    } else {
        drawArtwork(ctx, body: CGRect(x: 0, y: 0, width: s, height: s))
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) throws {
    let url = output.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

// macOS iconset names expected by iconutil, plus the iOS App Store icon.
let macSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
let iconset = output.appendingPathComponent("Figures.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in macSizes {
    try write(render(size: size, mac: true), "Figures.iconset/" + name)
}
try write(render(size: 1024, mac: false), "AppIcon-iOS-1024.png")
try write(render(size: 1024, mac: true), "AppIcon-macOS-1024.png")
print("Wrote icons to \(output.path)")
