import Foundation

/// Whether a new recording should fade the current answer, stop a pending
/// speech job outright, or do nothing. Playback outlives the job that started
/// it, so `isSpeaking` — not the job queue — is what matters here.
enum InterruptionDecision: Equatable {
    case fade, stop, none

    static func decide(isSpeaking: Bool, hasActiveSpeechJob: Bool) -> InterruptionDecision {
        if isSpeaking { return .fade }
        if hasActiveSpeechJob { return .stop }
        return .none
    }
}

/// How long the next answer waits before it speaks.
enum SpeechTiming {
    static func waitBeforeAnswer(interrupted: Bool) -> Duration {
        interrupted ? .seconds(1.5) : .zero
    }
}

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
