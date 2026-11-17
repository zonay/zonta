import Foundation

enum Transcribe {
    static func run(file: URL, settings: Settings) async throws -> String {
        let base = settings.whisperBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/audio/transcriptions") else {
            throw APIError.badURL(settings.whisperBaseURL)
        }

        let boundary = "ZontaBoundary\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let key = settings.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let audio = try Data(contentsOf: file)
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        field("model", settings.whisperModel)
        field("response_format", "json")
        let language = settings.whisperLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !language.isEmpty { field("language", language) }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let response = try await HTTP.post(
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body,
            timeout: request.timeoutInterval
        )
        let data = response.body

        if let obj = try? JSONDecoder().decode(Transcript.self, from: data) {
            let text = obj.text.trimmingCharacters(in: .whitespacesAndNewlines)
            await AppLog.shared.debug("Transcript: \(String(text.prefix(200)))", subsystem: "Whisper")
            return text
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { throw APIError.empty("Whisper returned no text.") }
        return raw
    }
}

private struct Transcript: Decodable { let text: String }

enum APIError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case empty(String)
    case offline(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "Bad URL: \(s)"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .empty(let s): return s
        case .offline(let host):
            return "Can't reach \(host). Allow Zonta under System Settings → Privacy & Security → Local Network, then try again."
        }
    }

    static func wrap(_ error: Error, url: URL) -> Error {
        let ns = error as NSError
        // -1009 offline, -1005 connection lost, 50 ENETDOWN — Local Network Privacy
        // reports a blocked LAN socket as "offline".
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorNotConnectedToInternet
            || ns.code == NSURLErrorNetworkConnectionLost
            || ns.code == 50 {
            return APIError.offline(url.host ?? url.absoluteString)
        }
        return error
    }

    static func check(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, String(body.prefix(400)))
        }
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
