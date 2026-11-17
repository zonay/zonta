import SwiftUI

/// One glass look for every Zonta surface. macOS 26+ uses the real Liquid
/// Glass effect; older systems fall back to a translucent material.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                content.background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
            }
        }
        .padding(8)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

/// The same glass treatment in a pill shape, for the activity indicator.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

extension View {
    func glassCapsule() -> some View {
        modifier(GlassCapsule())
    }
}

/// A pure round glass surface — no border, no shadow, no colour of its own.
struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: Circle())
            } else {
                content.background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}

extension View {
    func glassCircle() -> some View {
        modifier(GlassCircle())
    }
}
