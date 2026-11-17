import Foundation

/// Connectivity checks used by the settings window.
enum Probe {
    struct ModelsReply: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    struct StylesReply: Decodable {
        struct Style: Decodable { let name: String }
        let styles: [Style]
    }

    /// Lists the models an endpoint serves. Throws with a readable reason.
    static func models(baseURL: String, apiKey: String) async throws -> [String] {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/models") else {
            throw APIError.badURL(baseURL)
        }
        var headers: [String: String] = [:]
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }

        let response = try await HTTP.get(url: url, headers: headers, timeout: 8)

        if let reply = try? JSONDecoder().decode(ModelsReply.self, from: response.body) {
            return reply.data.map(\.id)
        }
        let raw = String(data: response.body, encoding: .utf8) ?? ""
        throw APIError.empty(raw.isEmpty ? "No models listed." : raw)
    }

    /// Lists the voice styles a speech server offers.
    static func voices(baseURL: String, apiKey: String) async throws -> [String] {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/styles") else {
            throw APIError.badURL(baseURL)
        }
        var headers: [String: String] = [:]
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }

        let response = try await HTTP.get(url: url, headers: headers, timeout: 8)

        if let reply = try? JSONDecoder().decode(StylesReply.self, from: response.body) {
            return reply.styles.map(\.name)
        }
        let raw = String(data: response.body, encoding: .utf8) ?? ""
        throw APIError.empty(raw.isEmpty ? "No voices listed." : raw)
    }
}
