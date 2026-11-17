import SwiftUI

enum ActivityState: Equatable {
    case none
    case chat
    case speech
}

/// A quiet, Siri-like glass circle: nothing but a slow rotating arc.
/// No icon, no text, no colour — just frosted glass and gentle motion.
struct ActivityIndicatorView: View {
    @State private var rotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.16), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    Color.primary.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }
        .padding(11)
        .frame(width: 48, height: 48)
        .glassCircle()
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }
}
