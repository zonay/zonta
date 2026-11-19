import Foundation

@main
struct AudioDuckerTests {
    @MainActor
    static func main() async throws {
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.count == AudioDucker.steps, "duck writes one value per step")
            check(writes.last == 0, "duck ends at zero")
            check(d.isDucked, "duck marks active")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            writes.removeAll()
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "restore ends at captured original")
            check(!d.isDucked, "restore clears active state")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            current = 0.3
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            writes.removeAll()
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "repeated duck keeps the first original")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            current = 0.5
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "restore wins over external volume change")
        }
        do {
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { nil }, writeVolume: { writes.append($0) })
            d.duck()
            try await Task.sleep(for: .milliseconds(100))
            check(writes.isEmpty, "nil volume produces no writes")
            check(!d.isDucked, "nil volume does not mark active")
            d.restore()
            check(writes.isEmpty, "restore without duck is a no-op")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            d.restore()
            try await Task.sleep(for: .milliseconds(100))
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            writes.removeAll()
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "interrupted restore keeps the true baseline")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(100))
            d.forceRestoreNow()
            check(writes.last == 0.8, "force restore writes the captured level immediately")
            check(!d.isDucked, "force restore clears ducked state")
        }
        do {
            let suite = UserDefaults(suiteName: "AudioDuckerTests-\(UUID().uuidString)")!
            AudioDucker.saveBaseline(0.73, defaults: suite)
            check(AudioDucker.savedBaseline(defaults: suite) == 0.73, "baseline persists")
            AudioDucker.clearSavedBaseline(defaults: suite)
            check(AudioDucker.savedBaseline(defaults: suite) == nil, "baseline can be cleared")
        }
        print("all audio ducker tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}
