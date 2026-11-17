import CoreGraphics
import Foundation

/// The Zonta mark: a Z whose diagonal is a wave.
///
/// Drawn in a unit box and scaled into whatever rectangle it is given, so the
/// same shape serves the app icon and the menu bar.
enum Mark {
    /// Stroke width as a fraction of the mark's size.
    static let strokeRatio: CGFloat = 0.13

    /// The mark path. `amplitude` bends the diagonal into a wave; 0 is a
    /// straight diagonal, larger values ripple it.
    static func path(
        in rect: CGRect,
        amplitude: CGFloat = 0,
        phase: CGFloat = 0,
        cycles: CGFloat = 1.5
    ) -> CGPath {
        let w = rect.width
        let h = rect.height

        // Both callers draw into a CG context (bottom-left origin), where a
        // larger y is visually higher. Inverting y here put the "top bar" at
        // the bottom and made the Z appear upside down.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        let path = CGMutablePath()

        // Top bar.
        path.move(to: point(0.07, 0.87))
        path.addLine(to: point(0.93, 0.87))

        // Bottom bar.
        path.move(to: point(0.07, 0.13))
        path.addLine(to: point(0.93, 0.13))

        // Diagonal, sampled from a straight line and pushed sideways by a
        // sine so it reads as a wave crossing the Z.
        let start = point(0.93, 0.87)
        let end = point(0.07, 0.13)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        // Unit normal to the diagonal.
        let nx = -dy / length
        let ny = dx / length

        let steps = 72
        var previous = start
        path.move(to: previous)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            var p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            if amplitude != 0 {
                // Taper at both ends so the wave blends into the bars.
                let taper = pow(sin(.pi * t), 0.55)
                let offset = amplitude * w * taper * sin(2 * .pi * cycles * t + phase)
                p.x += nx * offset
                p.y += ny * offset
            }
            path.addLine(to: p)
            previous = p
        }

        return path
    }

    /// Strokes the mark into a context.
    static func draw(
        in ctx: CGContext,
        rect: CGRect,
        color: CGColor,
        amplitude: CGFloat = 0,
        phase: CGFloat = 0,
        cycles: CGFloat = 1.5,
        lineWidth: CGFloat? = nil
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth ?? rect.width * strokeRatio)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path(in: rect, amplitude: amplitude, phase: phase, cycles: cycles))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
