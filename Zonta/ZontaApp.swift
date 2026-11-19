import AppKit
import AVFoundation
import SwiftUI

/// One answer the assistant spoke out loud. Kept so the user can re-read and
/// copy it later — the audio itself is thrown away after playback.
struct SpeechEntry: Identifiable {
    let id: UUID
    let question: String?
    let text: String
    let date: Date

    init(id: UUID = UUID(), question: String?, text: String, date: Date = Date()) {
        self.id = id
        self.question = question
        self.text = text
        self.date = date
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// Which hold produced the current recording.
    private enum Mode { case dictate, chat, translate }

    @Published var phase: Phase = .idle
    @Published var lastError: String?
    @Published var settings: Settings
    /// The conversation the chat feature is in. Nil until the first question.
    @Published var chatSessionID: String?
    /// Spoken answers, newest first. Shown in the floating speech panel.
    @Published var speechLog: [SpeechEntry] = []
    /// Whether chat answers are read out loud. Off still logs the answer.
    @Published var speechEnabled: Bool = SpeechOutput.enabled
    /// Whether dictated text is cleaned up before pasting. Off pastes raw text.
    @Published var cleanupEnabled: Bool = CleanupOutput.enabled
    /// Whether system audio eases down while a recording is in progress.
    @Published var duckAudioEnabled: Bool = AudioDuckOutput.enabled

    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let ducker = AudioDucker()
    private let queue = JobQueue.shared
    private var didBoot = false
    private var mode: Mode?
    /// Source of truth for the hold-to-talk state. Kept separate from `phase`
    /// so a job finishing can never pretend a new recording ended.
    @Published private var isRecording = false

    /// Recordings shorter than this are a stray modifier press, not speech.
    private static let minimumSpeech: TimeInterval = 0.6

    init() {
        settings = Settings.load()
        chatSessionID = ChatSession.id
    }

    func boot() {
        guard !didBoot else { return }
        didBoot = true
        // Repair a level left lowered by a crash or force quit.
        AudioDucker.restoreSavedBaseline()
        queue.onStateChange = { [weak self] in self?.refreshPhase() }
        queue.onError = { [weak self] title, message in
            self?.lastError = "\(title): \(message)"
        }
        AppLog.shared.info(
            "Accessibility granted: \(Pasteboard.accessibilityGranted)",
            subsystem: "Permissions"
        )
        if !Pasteboard.accessibilityGranted {
            Pasteboard.requestAccessibility()
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        // Bonjour browse registers the Local Network toggle. Do not open a
        // window or prompt when the grants are already there — a new window
        // on every launch is what made this feel like a permission loop.
        LocalNetwork.requestAccess()
        hotkey.onDown = { [weak self] key in self?.handleHotkeyDown(key) }
        hotkey.onUp = { [weak self] key in self?.handleHotkeyUp(key) }
        hotkey.onCancel = { [weak self] key in self?.handleHotkeyCancel(key) }
        hotkey.onDoubleTap = { [weak self] _ in self?.newChatThread() }
        applyHotkeyBindings()
        hotkey.start()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        AppLog.shared.info("Zonta \(version) booted", subsystem: "App")
    }

    /// Double-tap starts a new thread on whichever key currently holds chat.
    private func applyHotkeyBindings() {
        hotkey.configure(doubleTapKeys: settings.hotkeys.keys(for: .chat))
    }

    private func handleHotkeyDown(_ key: HotkeyKey) {
        switch settings.hotkeys.action(for: key) {
        case .chat: begin(.chat)
        case .dictate: begin(.dictate)
        case .translate: begin(.translate)
        case .off: break
        }
    }

    /// An Off key must not end a recording started by another key.
    private func handleHotkeyUp(_ key: HotkeyKey) {
        guard settings.hotkeys.isEnabled(key) else { return }
        end()
    }

    private func handleHotkeyCancel(_ key: HotkeyKey) {
        guard settings.hotkeys.isEnabled(key) else { return }
        cancel()
    }

    // MARK: - Recording

    private func begin(_ mode: Mode) {
        // The recorder, not `phase`, decides whether a hold is already open.
        // A job can change `phase` at any moment; ignoring that here is what
        // prevents a second message from leaving "Listening…" stuck.
        guard !recorder.isRecording else { return }
        if queue.hasActive(.speech) {
            // Old speech is stale once a new recording starts. Drop pending
            // answers; the ones already speaking are interrupted too.
            Speak.stop()
            queue.cancel(lane: .speech)
        }
        lastError = nil
        if mode != .chat { Pasteboard.rememberTarget() }
        do {
            try recorder.start()
            self.mode = mode
            isRecording = true
            refreshPhase()
            if duckAudioEnabled { ducker.duck() }
        } catch {
            handleError("Recorder", error)
        }
    }

    func end() {
        guard mode != nil, recorder.isRecording else { return }
        ducker.restore()
        let duration = recorder.recordedDuration
        let selectedMode = mode!
        guard let file = recorder.stop() else {
            mode = nil
            isRecording = false
            refreshPhase()
            return
        }
        mode = nil
        isRecording = false
        refreshPhase()

        guard duration >= Self.minimumSpeech else {
            AppLog.shared.warning(
                "Ignored a \(String(format: "%.1f", duration))s recording — too short.",
                subsystem: "Recorder"
            )
            return
        }

        let settings = self.settings
        // Chat and dictation/translation live in separate lanes. A dictation
        // never waits for a slow Hermes reply, and a new recording never
        // waits for the previous one's job chain.
        let lane: JobLane = selectedMode == .chat ? .chat : .dictation
        queue.enqueue(
            lane: lane, kind: .transcribe, title: "Transcribe recording"
        ) { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: file) }
            let transcript = try await Transcribe.run(file: file, settings: settings)
            try Task.checkCancellation()
            let question = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else {
                AppLog.shared.warning("Whisper returned an empty transcript.", subsystem: "Whisper")
                return
            }
            switch selectedMode {
            case .chat: self.enqueueChat(question, settings: settings)
            case .dictate: self.enqueueDictate(question, settings: settings)
            case .translate: self.enqueueTranslate(question, settings: settings)
            }
        }
    }

    /// A shortcut was pressed while the modifier was held. Drop the recording.
    func cancel() {
        if recorder.isRecording { _ = recorder.stop() }
        ducker.restore()
        mode = nil
        isRecording = false
        refreshPhase()
    }

    /// User-facing cancel for a long Hermes request (from the debug window).
    func cancelActiveJobs() {
        Speak.stop()
        queue.cancelAll()
        refreshPhase()
    }

    /// One place decides the menu-bar phase. A live recording always wins;
    /// otherwise the newest running job decides. Jobs never write `phase`
    /// directly, so they cannot clobber a hold that just started.
    private func refreshPhase() {
        let running = queue.runningJobs
        if isRecording {
            phase = .recording
            ActivityIndicatorWindow.shared.setState(.none)
            return
        }
        guard let kind = running.first?.kind else {
            phase = .idle
            ActivityIndicatorWindow.shared.setState(.none)
            return
        }
        switch kind {
        case .transcribe: phase = .transcribing
        case .chat: phase = .thinking
        case .dictate: phase = .sanitizing
        case .translate: phase = .translating
        case .speech: phase = .speaking
        }

        // Only chat and speech get a Siri-style pill; dictation stays quiet.
        let activity: ActivityState =
            running.contains { $0.lane == .speech } ? .speech
            : running.contains { $0.lane == .chat } ? .chat
            : .none
        ActivityIndicatorWindow.shared.setState(activity)
    }

    /// A typed follow-up from the speech panel goes straight into the chat
    /// lane — no recording, no transcription.
    func sendTextFollowUp(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        lastError = nil
        AppLog.shared.info(
            "Typed follow-up: \(String(question.prefix(120)))", subsystem: "Chat"
        )
        enqueueChat(question, settings: settings)
    }

    // MARK: - Queued modes

    private func enqueueChat(_ question: String, settings: Settings) {
        queue.enqueue(
            lane: .chat, kind: .chat, title: "Hermes reply"
        ) { [weak self] in
            guard let self else { return }
            // The gateway holds the conversation, not the request. It only
            // continues it when the request carries back the session id the
            // server handed out.
            let sessionID = ChatSession.id ?? ChatSession.newID()
            let reply = try await Sanitize.reply(
                question: question, settings: settings, sessionID: sessionID
            )
            try Task.checkCancellation()
            ChatSession.id = reply.sessionID ?? sessionID
            self.chatSessionID = ChatSession.id

            let answer = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                AppLog.shared.warning("Hermes returned an empty reply.", subsystem: "Chat")
                return
            }
            // Log before speaking so the answer survives a TTS failure.
            self.recordSpeech(text: answer, question: question)
            if self.speechEnabled {
                self.enqueueSpeech(answer, settings: settings)
            } else {
                AppLog.shared.debug("Speech is off; answer was only logged.", subsystem: "Speech")
            }
        }
    }

    private func enqueueSpeech(_ text: String, settings: Settings) {
        queue.enqueue(
            lane: .speech, kind: .speech, title: "Speak answer"
        ) {
            try await Speak.say(text, settings: settings)
            try Task.checkCancellation()
        }
    }

    private func enqueueDictate(_ transcript: String, settings: Settings) {
        // Snapshot the switch with the settings so toggling it mid-job cannot
        // change what this recording does.
        let cleanup = cleanupEnabled
        queue.enqueue(
            lane: .dictation,
            kind: .dictate,
            title: cleanup ? "Clean up & paste" : "Paste transcript"
        ) { [weak self] in
            guard let self else { return }
            var text = transcript
            if cleanup && !settings.sanitizePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    if let cleaned = try await Sanitize.run(transcript: transcript, settings: settings),
                       !cleaned.isEmpty { text = cleaned }
                } catch {
                    // Whisper already succeeded. Paste that and log why cleanup was skipped.
                    AppLog.shared.warning(
                        "Cleanup failed, pasting the raw transcript: \(error.localizedDescription)",
                        subsystem: "Dictate"
                    )
                }
            }
            try Task.checkCancellation()
            try self.paste(text)
        }
    }

    private func enqueueTranslate(_ text: String, settings: Settings) {
        queue.enqueue(
            lane: .dictation, kind: .translate, title: "Translate & paste"
        ) { [weak self] in
            guard let self else { return }
            let translated = try await Sanitize.translate(text: text, settings: settings)
            try Task.checkCancellation()
            guard !translated.isEmpty else {
                AppLog.shared.warning("Translation was empty.", subsystem: "Translate")
                return
            }
            try self.paste(translated)
        }
    }

    private func paste(_ text: String) throws {
        if let problem = Pasteboard.paste(text) {
            throw NSError(
                domain: "Zonta", code: 2,
                userInfo: [NSLocalizedDescriptionKey: problem]
            )
        }
    }

    /// Adds an answer to the floating panel and brings the panel up if needed.
    private func recordSpeech(text: String, question: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speechLog.insert(SpeechEntry(question: question, text: trimmed), at: 0)
        // Keep the panel bounded — it is meant to be a short scratch log.
        if speechLog.count > 200 {
            speechLog.removeLast(speechLog.count - 200)
        }
        AppLog.shared.info(
            "Answer ready (\(trimmed.count) chars): \(String(trimmed.prefix(120)))",
            subsystem: "Chat"
        )
        ActivityIndicatorWindow.shared.setState(.none)
        SpeechPanelWindow.shared.show(model: self)
    }

    func clearSpeechLog() {
        speechLog.removeAll()
    }

    /// Globe (fn) double-tap: drop the current thread without recording.
    private func newChatThread() {
        AppLog.shared.info("Globe double-tap: starting a new chat thread", subsystem: "Chat")
        newChatConversation()
    }

    /// Drops the current conversation. The next question starts a new one.
    func newChatConversation() {
        // An in-flight reply would write its old session id back into the
        // freshly reset conversation, so stop chat work first.
        queue.cancel(lane: .chat)
        ChatSession.reset()
        chatSessionID = nil
        refreshPhase()
        Notifier.shared.post(
            title: "New chat thread",
            body: "Hermes context cleared. Your next question starts fresh."
        )
        AppLog.shared.info("Started a new conversation", subsystem: "Chat")
    }

    func setSpeechEnabled(_ enabled: Bool) {
        guard enabled != speechEnabled else { return }
        speechEnabled = enabled
        SpeechOutput.enabled = enabled
        if enabled {
            AppLog.shared.info("Spoken answers enabled", subsystem: "Speech")
        } else {
            Speak.stop()
            queue.cancel(lane: .speech)
            AppLog.shared.info(
                "Spoken answers disabled; answers will only appear in the speech panel.",
                subsystem: "Speech"
            )
        }
    }

    func setCleanupEnabled(_ enabled: Bool) {
        guard enabled != cleanupEnabled else { return }
        cleanupEnabled = enabled
        CleanupOutput.enabled = enabled
        AppLog.shared.info(
            enabled ? "Cleanup enabled" : "Cleanup disabled; raw transcripts will be pasted.",
            subsystem: "Dictate"
        )
    }

    /// Best-effort synchronous restore when the app is about to quit.
    func forceRestoreAudioNow() {
        ducker.forceRestoreNow()
    }

    func setDuckAudioEnabled(_ enabled: Bool) {
        guard enabled != duckAudioEnabled else { return }
        duckAudioEnabled = enabled
        AudioDuckOutput.enabled = enabled
        if !enabled { ducker.restore() }
        AppLog.shared.info(
            enabled ? "Audio ducking enabled" : "Audio ducking disabled; audio stays at its current level.",
            subsystem: "Audio"
        )
    }

    func update(_ settings: Settings) {
        self.settings = settings
        applyHotkeyBindings()
    }

    private func handleError(_ context: String, _ error: Error) {
        let message = error.localizedDescription
        lastError = "\(context): \(message)"
        AppLog.shared.error("\(context): \(message)", subsystem: "App")
        if recorder.isRecording { _ = recorder.stop() }
        ducker.restore()
    }
}

@main
struct ZontaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Zonta") {
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear { model.boot() }
        }
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
    }
}

/// A standard, movable macOS window for the speech log. It has real traffic
/// lights (close / minimise / zoom), remembers its position, and is created on
/// the first answer. New answers just pile up inside its scroll view.
@MainActor
final class SpeechPanelWindow {
    static let shared = SpeechPanelWindow()
    private var controller: NSWindowController?

    var isVisible: Bool { controller?.window?.isVisible ?? false }

    func show(model: AppModel) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(rootView: SpeechLogView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = ""
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 412, height: 436))
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let margin: CGFloat = 18
            window.setFrameOrigin(NSPoint(x: visible.minX + margin, y: visible.minY + margin))
        }
        window.setFrameAutosaveName("ZontaSpeech")

        let wc = NSWindowController(window: window)
        controller = wc
        wc.showWindow(nil)
    }

    func hide() {
        controller?.window?.orderOut(nil)
    }
}

/// Borderless windows cannot become key by default; without that, clicking the
/// panel would not let the user select text or press ⌘C.
final class GlassPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A small, quiet pill in the top-right corner while Hermes thinks or the
/// answer is spoken. Shown only for those two states — dictation stays silent.
@MainActor
final class ActivityIndicatorWindow {
    static let shared = ActivityIndicatorWindow()
    private var controller: NSWindowController?
    private var current: ActivityState = .none

    func setState(_ state: ActivityState) {
        guard state != current else { return }
        current = state

        guard state != .none else {
            controller?.window?.orderOut(nil)
            return
        }

        let host = NSHostingController(rootView: ActivityIndicatorView())
        if let window = controller?.window {
            window.contentViewController = host
            Self.place(window)
            window.orderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isExcludedFromWindowsMenu = true
        window.setContentSize(Self.size)
        Self.place(window)
        let wc = NSWindowController(window: window)
        controller = wc
        window.orderFront(nil)
    }

    private static let size = NSSize(width: 48, height: 48)

    /// Reposition on every show from a fixed origin, so the chat and speech
    /// states always land on exactly the same spot.
    private static func place(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let xInset: CGFloat = 80
        let yInset: CGFloat = 120
        window.setFrameOrigin(NSPoint(
            x: visible.maxX - xInset - size.width,
            y: visible.maxY - yInset - size.height
        ))
    }
}

/// Shared setup for every glass window: transparent, borderless, floating.
@MainActor
private func configureGlassWindow(_ window: NSWindow, size: NSSize) {
    window.styleMask = [.borderless]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .floating
    window.isExcludedFromWindowsMenu = true
    window.setContentSize(size)
    window.center()
}

/// The debug window. Errors and warnings live here, alongside the live job
/// queue so a slow Hermes request is visible and cancellable.
@MainActor
enum AppLogWindow {
    private static var controller: NSWindowController?

    static func show() {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: AppLogView())
        let window = GlassPanelWindow(contentViewController: host)
        configureGlassWindow(window, size: NSSize(width: 796, height: 556))
        let wc = NSWindowController(window: window)
        controller = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hide() {
        controller?.window?.orderOut(nil)
    }
}

@MainActor
enum SettingsWindow {
    private static var controller: NSWindowController?

    /// Clicking the menu bar item opens this window, and closes it if it is
    /// already up.
    static func toggle(model: AppModel) {
        if let window = controller?.window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show(model: model)
    }

    static func show(model: AppModel) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "Zonta"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 656, height: 656))
        window.center()
        window.setFrameAutosaveName("ZontaSettings")
        // Barely-there transparency: the window still reads as solid, but the
        // glass content picks up a hint of what is behind it.
        window.alphaValue = 0.96
        let wc = NSWindowController(window: window)
        controller = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hide() {
        controller?.window?.orderOut(nil)
    }
}
