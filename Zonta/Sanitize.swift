import Foundation

enum Sanitize {
    /// Returns the model text, or nil when sanitation is disabled.
    static func run(transcript: String, settings: Settings) async throws -> String? {
        let prompt = settings.sanitizePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty { return nil }
        let reply = try await complete(
            system: prompt,
            user: transcript,
            config: settings.sanitizeLLM,
            sessionID: nil,
            timeout: 60
        )
        return reply.text
    }

    /// Spoken reply. Uses the chat prompt, and falls back to a short default.
    static func reply(
        question: String,
        settings: Settings,
        sessionID: String?
    ) async throws -> LLMReply {
        let prompt = settings.chatPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = prompt.isEmpty
            ? "Reply in the user's language, in two short spoken sentences. No markdown."
            : prompt
        // The chat endpoint is an agent gateway, so it gets real time to work.
        return try await complete(
            system: system,
            user: question,
            config: settings.chatLLM,
            sessionID: sessionID,
            timeout: 300
        )
    }

    /// Translates dictated text. The prompt carries the target language.
    static func translate(text: String, settings: Settings) async throws -> String {
        let prompt = settings.translatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = prompt.isEmpty
            ? "Translate the text into English. Return only the translation."
            : prompt
        let out = try await complete(
            system: system,
            user: text,
            config: settings.translateLLM,
            sessionID: nil,
            timeout: 60
        )
        return out.text
    }

    private static func complete(
        system: String,
        user: String,
        config: LLMConfig,
        sessionID: String?,
        timeout: TimeInterval
    ) async throws -> LLMReply {
        guard let url = config.chatURL else {
            throw APIError.badURL(config.baseURL)
        }

        let payload = ChatRequest(
            model: config.model,
            temperature: 0.2,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user),
            ],
            sendReasoningControls: config.reasoningControls != false
        )
        let body = try JSONEncoder().encode(payload)

        let response: HTTP.Response
        do {
            response = try await post(body, to: url, config: config, sessionID: sessionID, timeout: timeout)
        } catch let APIError.http(code, _) where code == 409 && sessionID != nil {
            // The session id belongs to another Hermes surface (the CLI, the
            // TUI) and the server refuses to attach to it. Mint a fresh id
            // and start a new conversation.
            await AppLog.shared.warning(
                "Hermes rejected the session id (409); starting a fresh conversation.",
                subsystem: "Chat"
            )
            response = try await post(
                body,
                to: url,
                config: config,
                sessionID: ChatSession.newID(),
                timeout: timeout
            )
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: response.body)
        let message = decoded.choices.first?.message

        // Reasoning models put the answer in reasoning_content and leave
        // content empty.
        let text = [message?.content, message?.reasoningContent]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        if text.isEmpty { throw APIError.empty("The model returned no text.") }
        return LLMReply(text: text, sessionID: response.headers[Self.sessionHeader])
    }

    /// The header the server uses to hand back the id of the conversation it
    /// is holding for this client.
    private static let sessionHeader = "x-hermes-session-id"

    private static func post(
        _ body: Data,
        to url: URL,
        config: LLMConfig,
        sessionID: String?,
        timeout: TimeInterval
    ) async throws -> HTTP.Response {
        var headers = config.headers
        if let id = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            headers["X-Hermes-Session-Id"] = id
        }
        return try await HTTP.post(url: url, headers: headers, body: body, timeout: timeout)
    }
}

/// A reply from the LLM, plus the conversation it belongs to.
struct LLMReply {
    let text: String
    /// The session id the server echoed back. Send it on the next turn to
    /// continue the same conversation.
    let sessionID: String?
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatRequest: Encodable {
    struct Thinking: Encodable {
        let budgetTokens: Int
    }

    let model: String
    let temperature: Double
    let messages: [ChatMessage]
    let sendReasoningControls: Bool

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case reasoningEffort = "reasoning_effort"
        case enableThinking = "enable_thinking"
        case thinkingBudget = "thinking_budget"
        case reasoningBudget = "reasoning_budget"
        case thinking
        case chatTemplateKwargs = "chat_template_kwargs"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(messages, forKey: .messages)
        guard sendReasoningControls else { return }
        // Reasoning models think by default and burn the whole reply on it.
        // Zero budget on every spelling LM Studio / llama.cpp / Gemini accept.
        try container.encode("none", forKey: .reasoningEffort)
        try container.encode(false, forKey: .enableThinking)
        try container.encode(0, forKey: .thinkingBudget)
        try container.encode(0, forKey: .reasoningBudget)
        try container.encode(Thinking(budgetTokens: 0), forKey: .thinking)
        try container.encode(["enable_thinking": false], forKey: .chatTemplateKwargs)
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let message: Message
    }
    let choices: [Choice]
}
