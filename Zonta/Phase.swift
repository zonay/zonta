import Foundation

/// What Zonta is doing right now.
enum Phase: String {
    case idle = "Ready"
    case recording = "Listening…"
    case transcribing = "Transcribing…"
    case sanitizing = "Cleaning…"
    case translating = "Translating…"
    case thinking = "Thinking…"
    case speaking = "Speaking…"
    case error = "Error"

    /// The menu bar mark ripples while work is in flight.
    var isAnimating: Bool {
        switch self {
        case .transcribing, .sanitizing, .translating, .thinking, .speaking:
            return true
        default:
            return false
        }
    }
}
