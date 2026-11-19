import AudioToolbox
import CoreAudio
import Foundation

/// Briefly eases the system output volume down while Zonta is recording, then
/// eases it back to the exact level it found. Read/write are injectable so the
/// ramp can be tested without touching real audio hardware.
@MainActor
final class AudioDucker {
    static let fadeDuration: Duration = .milliseconds(250)
    static let steps: Int = 10

    private nonisolated static let baselineKey = "audio.duck.baseline.v1"

    private let readVolume: () -> Float32?
    private let writeVolume: (Float32) -> Void
    /// The true system level. Kept until a restore ramp finishes uninterrupted,
    /// so a new hold during a restore cannot capture a mid-ramp value.
    private var baseline: Float32?
    private var duckActive = false
    private var rampID = 0
    private var rampTask: Task<Void, Never>?

    init(
        readVolume: @escaping () -> Float32? = AudioDucker.systemVolume,
        writeVolume: @escaping (Float32) -> Void = AudioDucker.setSystemVolume
    ) {
        self.readVolume = readVolume
        self.writeVolume = writeVolume
    }

    var isDucked: Bool { duckActive }

    func duck() {
        guard let current = readVolume(), current > 0 else { return }
        if baseline == nil {
            baseline = current
            Self.saveBaseline(current)
        }
        duckActive = true
        ramp(from: current, to: 0, id: nextRampID())
    }

    func restore() {
        guard let target = baseline else { return }
        duckActive = false
        let id = nextRampID()
        // Start from the live level: a restore mid-fade must not jump to zero.
        ramp(from: readVolume() ?? 0, to: target, id: id) { [weak self] in
            guard let self, self.rampID == id else { return }
            self.baseline = nil
            Self.saveBaseline(nil)
        }
    }

    /// Synchronous, best-effort restore for app termination. A ramp in flight
    /// is cancelled and the captured level is written immediately.
    func forceRestoreNow() {
        rampTask?.cancel()
        rampTask = nil
        rampID += 1
        if let target = baseline {
            writeVolume(target)
            baseline = nil
            Self.saveBaseline(nil)
        }
        duckActive = false
    }

    private func nextRampID() -> Int {
        rampID += 1
        return rampID
    }

    private func ramp(from start: Float32, to target: Float32, id: Int, onComplete: (() -> Void)? = nil) {
        rampTask?.cancel()
        rampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...Self.steps {
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled, self.rampID == id else { return }
                let t = Float32(step) / Float32(Self.steps)
                self.writeVolume(start + (target - start) * t)
            }
            onComplete?()
        }
    }

    // MARK: - Persistence (crash repair)

    nonisolated static func saveBaseline(_ value: Float32?, defaults: UserDefaults = .standard) {
        if let value {
            defaults.set(Double(value), forKey: baselineKey)
        } else {
            defaults.removeObject(forKey: baselineKey)
        }
    }

    nonisolated static func savedBaseline(defaults: UserDefaults = .standard) -> Float32? {
        guard let value = defaults.object(forKey: baselineKey) as? Double else { return nil }
        return Float32(value)
    }

    nonisolated static func clearSavedBaseline(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: baselineKey)
    }

    /// Reapplies a baseline left behind by a crash or force quit on next launch.
    nonisolated static func restoreSavedBaseline(defaults: UserDefaults = .standard) {
        guard let value = savedBaseline(defaults: defaults) else { return }
        setSystemVolume(value)
        clearSavedBaseline(defaults: defaults)
    }

    // MARK: - CoreAudio

    nonisolated static func systemVolume() -> Float32? {
        volume(for: defaultOutputDevice())
    }

    nonisolated static func setSystemVolume(_ value: Float32) {
        var address = volumeAddress()
        let device = defaultOutputDevice()
        var level = min(max(value, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectSetPropertyData(
            device, &address, 0, nil, size, &level
        )
    }

    private nonisolated static func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr ? device : AudioDeviceID()
    }

    private nonisolated static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private nonisolated static func volume(for device: AudioDeviceID) -> Float32? {
        var address = volumeAddress()
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            device, &address, 0, nil, &size, &level
        )
        return status == noErr ? level : nil
    }
}
