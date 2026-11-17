import SwiftUI

/// One palette for every Zonta surface. Orange is the accent; text uses
/// high-contrast colours so it stays readable on top of the glass material.
enum Theme {
    static let accent = Color.orange
    static let accentSoft = Color.orange.opacity(0.18)
    static let accentLine = Color.orange.opacity(0.35)
    static let ink = Color.primary
    static let muted = Color.primary.opacity(0.75)
    static let surface = Color.primary.opacity(0.10)
    static let surfaceStrong = Color.primary.opacity(0.15)
}

/// Filled orange button used for primary actions.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}
