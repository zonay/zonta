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
        print("all audio ducker tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}
