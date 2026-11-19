import Foundation

/// Eases an audio player's volume from its current level down to zero in
/// small steps. Pure enough to test without real audio hardware.
@MainActor
final class SpeechFade {
    nonisolated static let steps: Int = 10
    nonisolated static let duration: Duration = .milliseconds(250)

    private let write: (Float) -> Void

    init(write: @escaping (Float) -> Void) {
        self.write = write
    }

    /// The ramp values, ending exactly at zero.
    static func levels(from: Float, steps: Int = SpeechFade.steps) -> [Float] {
        (1...steps).map { i in from * (1 - Float(i) / Float(steps)) }
    }

    func run(from: Float) async {
        for level in Self.levels(from: from) {
            try? await Task.sleep(for: Self.duration / Self.steps)
            guard !Task.isCancelled else { return }
            write(level)
        }
    }
}
