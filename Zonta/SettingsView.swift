import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case dictation = "Dictation"
        case cleanup = "Cleanup"
        case chat = "Chat"
        case translate = "Translate"
        case speech = "Speech"
        case shortcuts = "Shortcuts"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .dictation: return "text.bubble"
            case .cleanup: return "wand.and.stars"
            case .chat: return "bubble.left.and.bubble.right"
            case .translate: return "character.book.closed"
            case .speech: return "speaker.wave.2"
            case .shortcuts: return "keyboard"
            }
        }
    }

    struct Result: Equatable {
        var ok: Bool
        var message: String
    }

    @ObservedObject var model: AppModel
    @State private var settings: Settings
    @State private var tab: Tab = .dictation
    @State private var results: [Tab: Result] = [:]
    @State private var busy: Tab?
    @State private var saveTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        _settings = State(initialValue: model.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Divider()

            Form {
                switch tab {
                case .dictation: dictationFields
                case .cleanup: cleanupFields
                case .chat: chatFields
                case .translate: translateFields
                case .speech: speechFields
                case .shortcuts: shortcutFields
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 330)

            Divider()
            footer
        }
        .frame(width: 640, height: 640)
        .glassSurface()
        .tint(Theme.accent)
        .onChange(of: settings) { _, _ in scheduleSave() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Zonta")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                    Text(model.phase.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.phase == .error ? Color.red : Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(model.phase == .error ? Color.red.opacity(0.20) : Theme.accentSoft)
                        )
                }
                Text(hotkeySummary)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Button {
                AppLogWindow.show()
            } label: {
                Label("App Log", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(AccentButtonStyle())
            .help("Open errors, warnings and the job queue")
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Zonta", systemImage: "power")
            }
            .buttonStyle(AccentButtonStyle())
            .help("Quit Zonta")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// One line describing the current key assignments for the header.
    private var hotkeySummary: String {
        let b = settings.hotkeys
        let active: [(String, HotkeyAction)] = [
            ("Globe", b.globe),
            ("Right ⌘", b.rightCommand),
            ("Right ⌥", b.rightOption),
        ].filter { $0.1 != .off }
        if active.isEmpty { return "All hotkeys off" }
        return active
            .map { "\($0.0) \($0.1.label.lowercased())" }
            .joined(separator: " · ")
    }

    // MARK: - Tabs

    @ViewBuilder
    private var dictationFields: some View {
        Section {
            TextField("Base URL", text: $settings.whisperBaseURL)
            KeyField("API key", text: $settings.whisperAPIKey)
            TextField("Model", text: $settings.whisperModel)
            TextField("Language", text: $settings.whisperLanguage)
        } header: {
            Label("Whisper server", systemImage: "waveform")
        } footer: {
            Text("Leave the language empty to let the model detect it. Press Right ⌘ to dictate.")
        }

        Section {
            TextEditor(text: $settings.whisperPrompt)
                .font(.body.monospaced())
                .frame(minHeight: 80)
        } header: {
            Label("Transcription prompt", systemImage: "text.quote")
        } footer: {
            Text("Sent as the optional `prompt` form field. Leave empty for models that do not accept it; speech models can use it for punctuation and capitalization.")
        }

        testSection(.dictation, action: "Test endpoint") {
            let models = try await Probe.models(
                baseURL: settings.whisperBaseURL,
                apiKey: settings.whisperAPIKey
            )
            return Result(ok: true, message: "Reachable. \(models.count) model(s): \(models.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private var cleanupFields: some View {
        Section {
            Toggle("Clean up dictated text", isOn: Binding(
                get: { model.cleanupEnabled },
                set: { model.setCleanupEnabled($0) }
            ))
        } header: {
            Label("Output", systemImage: "wand.and.stars")
        } footer: {
            Text("When off, the raw Whisper transcript is pasted with no cleanup call.")
        }

        Section {
            TextField("Base URL", text: $settings.sanitizeLLM.baseURL)
            KeyField("API key", text: $settings.sanitizeLLM.apiKey)
            TextField("Model", text: $settings.sanitizeLLM.model)
            Toggle("Send zero-reasoning controls", isOn: Binding(
                get: { settings.sanitizeLLM.reasoningControls != false },
                set: { settings.sanitizeLLM.reasoningControls = $0 }
            ))
        } header: {
            Label("LLM server", systemImage: "cpu")
        } footer: {
            Text("Any OpenAI-compatible chat endpoint. This one only tidies up dictated text.")
        }

        Section {
            TextEditor(text: $settings.sanitizePrompt)
                .font(.body.monospaced())
                .frame(minHeight: 130)
        } header: {
            Label("Prompt", systemImage: "text.quote")
        } footer: {
            Text("Sent as the system message, the transcript as the user message. Empty means paste the raw transcript with no cleanup.")
        }

        testSection(.cleanup, action: "Test endpoint") {
            let models = try await Probe.models(
                baseURL: settings.sanitizeLLM.baseURL,
                apiKey: settings.sanitizeLLM.apiKey
            )
            return Result(ok: true, message: "Reachable. \(models.count) model(s): \(models.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private var chatFields: some View {
        Section {
            TextField("Base URL", text: $settings.chatLLM.baseURL)
            KeyField("API key", text: $settings.chatLLM.apiKey)
            TextField("Model", text: $settings.chatLLM.model)
            Toggle("Send zero-reasoning controls", isOn: Binding(
                get: { settings.chatLLM.reasoningControls != false },
                set: { settings.chatLLM.reasoningControls = $0 }
            ))
            .help("Local model servers need these. A hosted agent gateway runs its own model, so turn them off there.")
        } header: {
            Label("LLM server", systemImage: "cpu")
        } footer: {
            Text("Independent of the cleanup model. Point it anywhere else, or run it on a different machine.")
        }

        Section {
            TextEditor(text: $settings.chatPrompt)
                .font(.body.monospaced())
                .frame(minHeight: 130)
        } header: {
            Label("Prompt", systemImage: "text.quote")
        } footer: {
            Text("How the assistant should answer. The reply is read out loud, so keep it short and plain.")
        }

        Section {
            HStack {
                if let id = model.chatSessionID {
                    Text(id)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("No conversation yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("New conversation") {
                    model.newChatConversation()
                }
                .disabled(model.chatSessionID == nil)
            }
        } header: {
            Label("Conversation", systemImage: "bubble.left.and.bubble.right")
        } footer: {
            Text("The gateway keeps the chat history on its side. Zonta sends the session id back on every question so the answers keep the thread. Start a new conversation to clear it.")
        }

        testSection(.chat, action: "Test endpoint") {
            let models = try await Probe.models(
                baseURL: settings.chatLLM.baseURL,
                apiKey: settings.chatLLM.apiKey
            )
            return Result(ok: true, message: "Reachable. \(models.count) model(s): \(models.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private var translateFields: some View {
        Section {
            TextField("Base URL", text: $settings.translateLLM.baseURL)
            KeyField("API key", text: $settings.translateLLM.apiKey)
            TextField("Model", text: $settings.translateLLM.model)
            Toggle("Send zero-reasoning controls", isOn: Binding(
                get: { settings.translateLLM.reasoningControls != false },
                set: { settings.translateLLM.reasoningControls = $0 }
            ))
        } header: {
            Label("LLM server", systemImage: "cpu")
        } footer: {
            Text("Independent of the cleanup and chat models. Point it anywhere else, or run it on a different machine.")
        }

        Section {
            TextEditor(text: $settings.translatePrompt)
                .font(.body.monospaced())
                .frame(minHeight: 130)
        } header: {
            Label("Prompt", systemImage: "text.quote")
        } footer: {
            Text("Say which language to translate into. The prompt is the system message, the dictated text is the user message. The translation is pasted where the cursor is.")
        }

        testSection(.translate, action: "Test endpoint") {
            let models = try await Probe.models(
                baseURL: settings.translateLLM.baseURL,
                apiKey: settings.translateLLM.apiKey
            )
            return Result(ok: true, message: "Reachable. \(models.count) model(s): \(models.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private var speechFields: some View {
        Section {
            Toggle("Speak answers out loud", isOn: Binding(
                get: { model.speechEnabled },
                set: { model.setSpeechEnabled($0) }
            ))
        } header: {
            Label("Output", systemImage: "speaker.wave.2")
        } footer: {
            Text("When off, answers are still shown in the speech panel so you can read and copy them.")
        }

        Section {
            TextField("Base URL", text: $settings.ttsBaseURL)
            KeyField("API key", text: $settings.ttsAPIKey)
            TextField("Model", text: $settings.ttsModel)
            TextField("Language", text: $settings.ttsLanguage)
        } header: {
            Label("Speech server", systemImage: "speaker.wave.2")
        } footer: {
            HStack {
                Text("Leave the language empty to let the model decide.")
                Spacer()
                Button("Re-request Local Network") {
                    LocalNetwork.requestAccessAgain()
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
        }

        Section {
            TextField("Voice name", text: $settings.ttsVoice)
                .textFieldStyle(.roundedBorder)
        } header: {
            Label("Voice", systemImage: "waveform")
        } footer: {
            Text("The voice name is sent to the speech server as-is.")
        }

        testSection(.speech, action: "Speak a test phrase") {
            try await Speak.say("Testing. One, two, three.", settings: settings)
            return Result(ok: true, message: "Spoken with voice \(settings.ttsVoice).")
        }
    }

    @ViewBuilder
    private var shortcutFields: some View {
        Section {
            Picker("Globe", selection: $settings.hotkeys.globe) {
                ForEach(HotkeyAction.allCases) { action in
                    Text(action.label).tag(action)
                }
            }
            Picker("Right ⌘", selection: $settings.hotkeys.rightCommand) {
                ForEach(HotkeyAction.allCases) { action in
                    Text(action.label).tag(action)
                }
            }
            Picker("Right ⌥", selection: $settings.hotkeys.rightOption) {
                ForEach(HotkeyAction.allCases) { action in
                    Text(action.label).tag(action)
                }
            }
        } header: {
            Label("Keyboard shortcuts", systemImage: "keyboard")
        } footer: {
            Text("Double-tap the Chat key to start a new thread. Choose Off to disable a key. Changes apply as soon as you save.")
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func testSection(
        _ tab: Tab,
        action: String,
        run: @escaping () async throws -> Result
    ) -> some View {
        Section {
            HStack {
                Button(action: { test(tab, run: run) }) {
                    if busy == tab {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(action)
                    }
                }
                .disabled(busy != nil)
                if let result = results[tab] {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.ok ? Color.green : Color.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to defaults") {
                settings = .defaults
                model.newChatConversation()
                results = [:]
            }
            .buttonStyle(.link)
            Spacer()
            Text("Saved automatically")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            settings.save()
            model.update(settings)
        }
    }

    private func test(_ tab: Tab, run: @escaping () async throws -> Result) {
        busy = tab
        results[tab] = nil
        Task { @MainActor in
            let outcome: Result
            do {
                outcome = try await run()
            } catch {
                outcome = Result(ok: false, message: error.localizedDescription)
            }
            results[tab] = outcome
            busy = nil
        }
    }
}

/// A secret field with a show and hide toggle.
struct KeyField: View {
    @Binding var text: String
    let title: String
    @State private var revealed = false

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(revealed ? "Hide" : "Show")
        }
    }
}
