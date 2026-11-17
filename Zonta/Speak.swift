import AVFoundation
import Foundation

enum Speak {
    private static var player: AVAudioPlayer?
    private static let lock = NSLock()

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

    static func stop() {
        lock.lock()
        player?.stop()
        player = nil
        lock.unlock()
    }

    @MainActor
    private static func play(_ file: URL) throws {
        let audio = try AVAudioPlayer(contentsOf: file)
        audio.prepareToPlay()
        lock.lock()
        player?.stop()
        player = audio
        lock.unlock()
        audio.play()
        // The player retains itself via `player` for the duration; drop the file later.
        DispatchQueue.main.asyncAfter(deadline: .now() + audio.duration + 1) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
