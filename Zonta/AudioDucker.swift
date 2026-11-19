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

    private let readVolume: () -> Float32?
    private let writeVolume: (Float32) -> Void
    private var original: Float32?
    private var rampTask: Task<Void, Never>?

    init(
        readVolume: @escaping () -> Float32? = AudioDucker.systemVolume,
        writeVolume: @escaping (Float32) -> Void = AudioDucker.setSystemVolume
    ) {
        self.readVolume = readVolume
        self.writeVolume = writeVolume
    }

    var isDucked: Bool { original != nil }

    func duck() {
        guard original == nil, let current = readVolume(), current > 0 else { return }
        original = current
        ramp(from: current, to: 0)
    }

    func restore() {
        guard let target = original else { return }
        original = nil
        // Start from the live level: a restore mid-fade must not jump to zero.
        ramp(from: readVolume() ?? 0, to: target)
    }

    private func ramp(from start: Float32, to target: Float32) {
        rampTask?.cancel()
        rampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...Self.steps {
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled else { return }
                let t = Float32(step) / Float32(Self.steps)
                self.writeVolume(start + (target - start) * t)
            }
        }
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
