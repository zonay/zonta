import AppKit
import CoreGraphics
import Foundation

/// Menu bar images. Not the standard microphone: a Z with a wave diagonal.
///
/// Idle and working states are template images, so macOS paints them black on
/// light and white on dark. Recording is tinted red so it is obvious at a
/// glance that the microphone is live.
enum MenuIcon {
    @MainActor
    static func image(for phase: Phase, wavePhase: CGFloat = 0) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let tint: NSColor

        switch phase {
        case .recording:
            tint = .systemRed
        case .error:
            tint = .systemOrange
        default:
            tint = .black
        }

        let amplitude: CGFloat
        switch phase {
        case .recording: amplitude = 0.05
        case .transcribing, .sanitizing, .translating, .thinking: amplitude = 0.045
        case .speaking: amplitude = 0.07
        default: amplitude = 0.025
        }

        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.5, dy: 2.5)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            // Template images are drawn in black; the tint only matters for
            // the states that are not templates.
            let color = tint.cgColor
            Mark.draw(in: ctx, rect: inset, color: color, amplitude: amplitude, phase: wavePhase)
            ctx.restoreGState()
            return true
        }

        image.isTemplate = (phase != .recording && phase != .error)
        return image
    }
}
