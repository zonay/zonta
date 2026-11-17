import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the menu bar mark at 18pt, scaled up, so it can be looked at.

@main
struct Preview {
    static func main() {
        let size = NSSize(width: 18, height: 18)
        let scale = 8
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
                      ? CommandLine.arguments[1]
                      : "build/menuicon.png")

        let variants: [(String, Phase)] = [
            ("idle", .idle),
            ("recording", .recording),
            ("working", .transcribing),
            ("speaking", .speaking),
            ("error", .error),
        ]

        let width = Int(size.width) * scale
        let height = Int(size.height) * scale
        guard let ctx = CGContext(
            data: nil,
            width: width * variants.count,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width * variants.count, height: height))

        for (index, item) in variants.enumerated() {
            let image = MenuIcon.image(for: item.1, wavePhase: 0.8)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(index * width), y: 0)
            ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            ctx.restoreGState()
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(out.path)")
    }
}
