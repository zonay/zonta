import AVFoundation
import Foundation

enum Speak {
    private static var player: AVAudioPlayer?
    private static let lock = NSLock()
    private static var fadeTask: Task<Void, Never>?

    @MainActor static var isPlaying: Bool { player?.isPlaying ?? false }

    /// Eases the current answer down to silence, then stops it. An existing
    /// fade is cancelled first so only the latest interruption wins.
    @MainActor static func fadeOutAndStop() {
        guard player != nil else { return }
        fadeTask?.cancel()
        let from = player?.volume ?? 1
        fadeTask = Task { @MainActor in
            let fader = SpeechFade { level in
                MainActor.assumeIsolated { player?.volume = level }
            }
            await fader.run(from: from)
            guard !Task.isCancelled else { return }
            hardStop()
        }
    }

    /// Synthesises `text` on the configured speech service and plays it. A new
    /// call stops the previous one.
    static func say(_ text: String, settings: Settings) async throws {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if spoken.isEmpty { throw APIError.empty("Nothing to say.") }

        let base = settings.ttsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/audio/speech") else {
            throw APIError.badURL(settings.ttsBaseURL)
        }

        var body: [String: String] = [
            "model": settings.ttsModel,
            "input": spoken,
            "voice": settings.ttsVoice,
            "response_format": "wav",
        ]
        let lang = settings.ttsLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lang.isEmpty { body["lang"] = lang }

        var headers = ["Content-Type": "application/json"]
        let key = settings.ttsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }

        await AppLog.shared.debug(
            "TTS request: \(String(spoken.prefix(120)))\(spoken.count > 120 ? "…" : "")",
            subsystem: "Speech"
        )
        let response = try await HTTP.post(
            url: url,
            headers: headers,
            body: try JSONEncoder().encode(body),
            timeout: 60
        )

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("zonta-say-\(UUID().uuidString).wav")
        try response.body.write(to: file)
        try await MainActor.run {
            try play(file)
        }
    }

    @MainActor static func stop() {
        fadeTask?.cancel()
        fadeTask = nil
        hardStop()
    }

    @MainActor private static func hardStop() {
        lock.lock()
        player?.stop()
        player = nil
        lock.unlock()
    }

    @MainActor
    private static func play(_ file: URL) throws {
        let audio = try AVAudioPlayer(contentsOf: file)
        audio.prepareToPlay()
        // A fade still in flight must not attenuate this new playback.
        stop()
        lock.lock()
        player = audio
        lock.unlock()
        audio.play()
        // The player retains itself via `player` for the duration; drop the file later.
        DispatchQueue.main.asyncAfter(deadline: .now() + audio.duration + 1) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
