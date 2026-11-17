import Foundation

/// An OpenAI-compatible chat endpoint. The cleanup pass and the chat reply
/// each own one of these, so they can point at different servers and models.
struct LLMConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var model: String
    /// Whether to send the zero-reasoning-budget fields. Local model servers
    /// want them; a hosted agent gateway runs its own model and ignores them.
    /// `nil` means send them.
    var reasoningControls: Bool?

    private var base: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var chatURL: URL? { URL(string: base + "/chat/completions") }
    var modelsURL: URL? { URL(string: base + "/models") }

    var headers: [String: String] {
        var h = ["Content-Type": "application/json"]
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { h["Authorization"] = "Bearer \(key)" }
        return h
    }
}

/// Whether answers are spoken out loud. Kept outside `Settings` so adding the
/// flag does not invalidate the existing `settings.v4` blob.
enum SpeechOutput {
    private static let key = "speech.enabled.v1"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The conversation the chat feature is currently in.
///
/// Hermes keeps the chat history in its own session store, not in the request
/// body. It only continues a conversation when the request carries back the
/// `X-Hermes-Session-Id` the server handed out. Without that header the
/// server derives a session from the system prompt and the first user
/// message, so every question lands in a brand new session and the agent
/// starts from zero each time.
///
/// The id lives here, outside of `Settings`, because the settings window
/// rewrites `Settings` wholesale and would drop the session on every save.
enum ChatSession {
    private static let key = "chat.session.v1"

    /// The id of the current conversation, or nil when there is none.
    static var id: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: key) ?? ""
            return stored.isEmpty ? nil : stored
        }
        set {
            let value = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    /// An id for a new conversation. The server accepts a client chosen id
    /// and echoes it back on every turn.
    static func newID() -> String {
        "zonta-\(UUID().uuidString)"
    }

    /// Forgets the conversation. The next question starts a fresh one.
    static func reset() {
        id = nil
    }
}

struct Settings: Codable, Equatable {
    // Dictation — Whisper
    var whisperBaseURL: String
    var whisperAPIKey: String
    var whisperModel: String
    var whisperLanguage: String

    // Cleanup — the LLM that tidies up a dictated transcript
    var sanitizeLLM: LLMConfig
    var sanitizePrompt: String

    // Chat — the LLM that answers a spoken question
    var chatLLM: LLMConfig
    var chatPrompt: String

    // Translate — the LLM that translates a dictated phrase
    var translateLLM: LLMConfig
    var translatePrompt: String

    // Speech — text to speech
    var ttsBaseURL: String
    var ttsAPIKey: String
    var ttsModel: String
    var ttsVoice: String
    var ttsLanguage: String

    static let defaults = Settings(
        whisperBaseURL: "http://localhost:6667/v1",
        whisperAPIKey: "",
        whisperModel: "whisper-large-v3-turbo",
        whisperLanguage: "",
        sanitizeLLM: LLMConfig(
            baseURL: "http://localhost:1235/v1",
            apiKey: "",
            model: "google/gemma-4-12b-qat"
        ),
        sanitizePrompt: """
        Rewrite the dictated transcript into clean, natural text. \
        Fix punctuation, casing, and obvious speech-to-text mistakes. \
        Do not add facts, do not answer questions, do not explain. \
        Return only the rewritten text.
        """,
        chatLLM: LLMConfig(
            baseURL: "http://localhost:8642/v1",
            apiKey: "",
            model: "hermes-agent",
            reasoningControls: false
        ),
        chatPrompt: """
        You are a voice assistant. Reply to the user's spoken question in the \
        same language they used. Two or three short sentences, plain spoken \
        language, no markdown, no lists, no preamble.
        """,
        translateLLM: LLMConfig(
            baseURL: "http://localhost:1235/v1",
            apiKey: "",
            model: "google/gemma-4-12b-qat"
        ),
        translatePrompt: """
        Translate the text into English. Keep the meaning, the tone, and the \
        formatting. If the text is already English, return it unchanged. \
        Return only the translation.
        """,
        ttsBaseURL: "http://localhost:7788/v1",
        ttsAPIKey: "",
        ttsModel: "supertonic-3",
        ttsVoice: "voice one",
        ttsLanguage: ""
    )

    private static let key = "settings.v4"
    private static let v3Key = "settings.v3"
    private static let v2Key = "settings.v2"
    private static let legacyKey = "settings.v1"

    /// Old builds shipped "M1" as the default voice. Move that (and an empty
    /// value) to the new default without touching a deliberately typed name.
    private static func normalizeVoice(_ settings: Settings) -> Settings {
        var result = settings
        let current = result.ttsVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == "M1" {
            result.ttsVoice = "voice one"
        }
        return result
    }

    static func load() -> Settings {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            return normalizeVoice(decoded)
        }
        if let data = UserDefaults.standard.data(forKey: v3Key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            // The chat endpoint moved from the local model to a separate
            // gateway in v4. Keep the user's prompt, adopt the new defaults.
            decoded.save()
            UserDefaults.standard.removeObject(forKey: v3Key)
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: v2Key),
           var decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            // The chat endpoint moved from the local model to the hermes
            // agent gateway. The prompt the user wrote stays.
            decoded.chatLLM = Settings.defaults.chatLLM
            decoded.save()
            UserDefaults.standard.removeObject(forKey: v2Key)
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            let migrated = legacy.migrated()
            migrated.save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return migrated
        }
        return .defaults
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Shape written by older builds, where one LLM served both jobs.
private struct LegacySettings: Decodable {
    var whisperBaseURL: String
    var whisperAPIKey: String
    var whisperModel: String
    var whisperLanguage: String
    var gemmaBaseURL: String
    var gemmaAPIKey: String
    var gemmaModel: String
    var sanitizePrompt: String
    var ttsBaseURL: String
    var ttsAPIKey: String

    func migrated() -> Settings {
        let llm = LLMConfig(baseURL: gemmaBaseURL, apiKey: gemmaAPIKey, model: gemmaModel)
        var result = Settings.defaults
        result.whisperBaseURL = whisperBaseURL
        result.whisperAPIKey = whisperAPIKey
        result.whisperModel = whisperModel
        result.whisperLanguage = whisperLanguage
        result.sanitizeLLM = llm
        result.sanitizePrompt = sanitizePrompt
        result.chatLLM = llm
        result.ttsBaseURL = ttsBaseURL
        result.ttsAPIKey = ttsAPIKey
        return result
    }
}
