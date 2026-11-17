import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the Zonta app icon into an .iconset directory.
///
/// A flat, modern look: a rounded square with a soft gradient and the Z wave
/// mark in white. Run it, then `iconutil -c icns` on the output.

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

func renderIcon(size: Int) -> CGImage? {
    let pixels = CGFloat(size)
    guard let ctx = CGContext(
        data: nil,
        width: Int(pixels),
        height: Int(pixels),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Apple's macOS icon grid: the shape is 824/1024 of the canvas, centred.
    let inset = pixels * (1 - 824.0 / 1024.0) / 2
    let shape = CGRect(x: inset, y: inset, width: pixels - inset * 2, height: pixels - inset * 2)
    let radius = shape.width * (185.0 / 824.0)

    let shapePath = CGPath(
        roundedRect: shape,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    ctx.saveGState()
    ctx.addPath(shapePath)
    ctx.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 1),   // #6B5CF6
            CGColor(red: 0.55, green: 0.27, blue: 0.94, alpha: 1),   // #8C45F0
            CGColor(red: 0.24, green: 0.42, blue: 0.96, alpha: 1),   // #3D6BF5
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: shape.minX, y: shape.maxY),
        end: CGPoint(x: shape.maxX, y: shape.minY),
        options: []
    )

    // Soft light from the top left, so the flat square has some depth.
    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: shape.minX + shape.width * 0.26, y: shape.maxY - shape.height * 0.22),
        startRadius: 0,
        endCenter: CGPoint(x: shape.minX + shape.width * 0.26, y: shape.maxY - shape.height * 0.22),
        endRadius: shape.width * 0.78,
        options: []
    )

    // The mark.
    let markSize = shape.width * 0.54
    let markRect = CGRect(
        x: shape.midX - markSize / 2,
        y: shape.midY - markSize / 2,
        width: markSize,
        height: markSize
    )
    Mark.draw(
        in: ctx,
        rect: markRect,
        color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        amplitude: 0.095,
        cycles: 1.25,
        lineWidth: markSize * 0.145
    )

    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

@main
struct IconGen {
    static func main() {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            FileHandle.standardError.write("usage: icongen <iconset-dir>\n".data(using: .utf8)!)
            exit(1)
        }
        let dir = URL(fileURLWithPath: args[1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (name, pixels) in sizes {
            guard let image = renderIcon(size: pixels) else {
                FileHandle.standardError.write("failed at \(name)\n".data(using: .utf8)!)
                exit(1)
            }
            write(image, to: dir.appendingPathComponent("\(name).png"))
        }

        print("wrote \(sizes.count) images to \(dir.path)")
    }
}
