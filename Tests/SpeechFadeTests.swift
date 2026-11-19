import Foundation

@main
struct SpeechFadeTests {
    @MainActor
    static func main() async throws {
        let levels = SpeechFade.levels(from: 1)
        check(levels.count == SpeechFade.steps, "one level per step")
        check(levels.last == 0, "levels end at zero")
        check(levels == levels.sorted(by: >=), "levels decrease monotonically")
        check(SpeechFade.levels(from: 0.5).first! == 0.45, "first step starts at the current level")
        check(SpeechTiming.waitBeforeAnswer(interrupted: true) == .seconds(1.5), "interrupted answer waits 1.5s")
        check(SpeechTiming.waitBeforeAnswer(interrupted: false) == .zero, "normal answer has no wait")
        check(InterruptionDecision.decide(isSpeaking: true, hasActiveSpeechJob: false) == .fade, "playing answer fades even with no active speech job")
        check(InterruptionDecision.decide(isSpeaking: false, hasActiveSpeechJob: true) == .stop, "pending speech job is hard-stopped")
        check(InterruptionDecision.decide(isSpeaking: false, hasActiveSpeechJob: false) == .none, "no speech means no interruption")

        do {
            var writes: [Float] = []
            let fade = SpeechFade { writes.append($0) }
            await fade.run(from: 1)
            check(writes.count == SpeechFade.steps, "run writes one value per step")
            check(writes.last == 0, "run writes the final zero")
        }
        do {
            var writes: [Float] = []
            let fade = SpeechFade { writes.append($0) }
            let task = Task { @MainActor in await fade.run(from: 1) }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            let countAtCancel = writes.count
            try await Task.sleep(for: .milliseconds(250))
            check(writes.count == countAtCancel, "cancelling a run stops further writes")
        }
        print("all speech fade tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}
