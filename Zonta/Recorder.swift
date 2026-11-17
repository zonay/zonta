import AVFoundation
import Foundation

/// Records the default input as 16 kHz mono 16-bit PCM WAV, which Whisper likes.
final class Recorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var url: URL?
    private var startedAt: Date?
    private let queue = DispatchQueue(label: "app.zonta.Zonta.record")

    var isRecording: Bool { url != nil }

    /// Seconds of audio captured so far. Read before stopping.
    var recordedDuration: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    func start() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw RecorderError.needsPermission
        case .denied, .restricted:
            throw RecorderError.micDenied
        @unknown default:
            break
        }

        let input = engine.inputNode
        let src = input.outputFormat(forBus: 0)
        guard src.sampleRate > 0, src.channelCount > 0 else {
            throw RecorderError.noInput
        }

        let dst = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
        guard let converter = AVAudioConverter(from: src, to: dst) else {
            throw RecorderError.noConverter
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("zonta-\(UUID().uuidString).wav")
        let audioFile = try AVAudioFile(
            forWriting: out,
            settings: dst.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        file = audioFile
        url = out
        startedAt = Date()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: src) { [weak self] buffer, _ in
            // The tap buffer is only valid until this callback returns.
            guard let copy = Self.copy(buffer) else { return }
            self?.queue.async {
                self?.write(copy, converter: converter, dst: dst, file: audioFile)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let finished = url
        queue.sync { }
        file = nil
        url = nil
        startedAt = nil
        return finished
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let srcList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let dstList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in 0..<srcList.count {
            let bytes = Int(srcList[i].mDataByteSize)
            dstList[i].mDataByteSize = srcList[i].mDataByteSize
            guard bytes > 0, let src = srcList[i].mData, let dst = dstList[i].mData else { continue }
            dst.copyMemory(from: src, byteCount: bytes)
        }
        return copy
    }

    private func write(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        dst: AVAudioFormat,
        file: AVAudioFile
    ) {
        let ratio = dst.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, converted.frameLength > 0 {
            try? file.write(from: converted)
        }
    }
}

enum RecorderError: LocalizedError {
    case noInput
    case noConverter
    case needsPermission
    case micDenied

    var errorDescription: String? {
        switch self {
        case .noInput: return "No microphone input format."
        case .noConverter: return "Could not build the audio converter."
        case .needsPermission: return "Allow microphone access, then hold Globe again."
        case .micDenied: return "Microphone access is off. Enable it in System Settings → Privacy → Microphone."
        }
    }
}
