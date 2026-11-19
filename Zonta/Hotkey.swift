import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Hold-to-talk for the modifier keys that are not already busy typing.
///
/// A modifier only counts as a hold when it is pressed for a moment and no
/// other key follows. Option in particular is how accented characters are
/// typed, so Option+e must never start a recording. A session event tap
/// catches that other key and cancels the pending start.
///
/// Globe fires immediately on press and release. Right Command and Right
/// Option use a short hold delay. A quick double-press of a configured key
/// fires `onDoubleTap` (new chat thread) instead of a hold.
@MainActor
final class Hotkey {
    var onDown: ((HotkeyKey) -> Void)?
    var onUp: ((HotkeyKey) -> Void)?
    var onCancel: ((HotkeyKey) -> Void)?
    var onDoubleTap: ((HotkeyKey) -> Void)?

    private var monitor: Any?
    private var global: Any?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Keys whose quick double-press means "new chat thread".
    private var doubleTapKeys: Set<HotkeyKey> = []
    private var lastPress: [HotkeyKey: Date] = [:]
    private var suppressed: Set<HotkeyKey> = []
    private var pressed: Set<HotkeyKey> = []
    private var pending: HotkeyKey?
    private var active: HotkeyKey?
    private var pendingTask: Task<Void, Never>?

    /// How long a modifier must be held before it counts.
    private static let holdDelay: Duration = .milliseconds(250)

    private static let modifierKeyCodes: Set<Int> = [
        Int(kVK_Shift), Int(kVK_RightShift),
        Int(kVK_Control), Int(kVK_RightControl),
        Int(kVK_Option), Int(kVK_RightOption),
        Int(kVK_Command), Int(kVK_RightCommand),
        Int(kVK_Function),
    ]

    /// Applies the current bindings. Ends any hold that is still active so a
    /// live rebind cannot leave the recorder running with no release to come.
    /// `pressed` is kept: it mirrors the physical keys and lets the release of
    /// a key held across the rebind be seen as a release, not a new press.
    func configure(doubleTapKeys: Set<HotkeyKey>) {
        if let active { onCancel?(active) }
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
        active = nil
        lastPress.removeAll()
        suppressed.removeAll()
        self.doubleTapKeys = doubleTapKeys
    }

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // NSEvent monitors fire on the main thread.
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        installTap()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let global { NSEvent.removeMonitor(global) }
        monitor = nil
        global = nil
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
        active = nil
        lastPress.removeAll()
        suppressed.removeAll()
        pressed.removeAll()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        process(key: .globe, pressed: event.modifierFlags.contains(.function))

        let side: HotkeyKey
        switch event.keyCode {
        case UInt16(kVK_RightCommand): side = .rightCommand
        case UInt16(kVK_RightOption): side = .rightOption
        default: return
        }
        let isPressed: Bool
        switch side {
        case .rightCommand: isPressed = event.modifierFlags.contains(.command)
        case .rightOption: isPressed = event.modifierFlags.contains(.option)
        case .globe: return
        }
        process(key: side, pressed: isPressed)
    }

    /// Edge-triggered press/release handling shared by every key.
    /// Internal so the state machine can be exercised by tests.
    func process(key: HotkeyKey, pressed isPressed: Bool) {
        guard isPressed != pressed.contains(key) else { return }

        if isPressed {
            pressed.insert(key)

            if doubleTapKeys.contains(key),
               let last = lastPress[key],
               Date().timeIntervalSince(last) <= NSEvent.doubleClickInterval {
                // Two quick presses: skip the hold on this press and ignore
                // its release. A third press is a fresh hold again.
                lastPress[key] = nil
                suppressed.insert(key)
                cancelPending()
                if active == key { active = nil }
                onDoubleTap?(key)
                return
            }

            lastPress[key] = Date()
            if key == .globe {
                onDown?(key)
            } else {
                beginHold(key)
            }
        } else {
            pressed.remove(key)
            if suppressed.contains(key) {
                suppressed.remove(key)
                return
            }
            if key == .globe {
                onUp?(key)
            } else {
                release(key)
            }
        }
    }

    fileprivate func handleTap(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(CGEventField.keyboardEventKeycode))
        guard !Self.modifierKeyCodes.contains(keyCode) else { return }
        // Another key went down while a modifier was held. That is a shortcut,
        // not a recording.
        if pending != nil {
            cancelPending()
        } else if active != nil {
            abort()
        }
    }

    // MARK: - Hold state

    private func beginHold(_ key: HotkeyKey) {
        pendingTask?.cancel()
        pending = key
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Hotkey.holdDelay)
            guard let self, !Task.isCancelled, self.pending == key, self.active == nil else { return }
            self.pending = nil
            self.active = key
            self.onDown?(key)
        }
    }

    private func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
    }

    private func release(_ key: HotkeyKey) {
        cancelPending()
        guard active == key else { return }
        active = nil
        onUp?(key)
    }

    private func abort() {
        cancelPending()
        guard let key = active else { return }
        active = nil
        onCancel?(key)
    }

    // MARK: - Key tap

    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }
}

private let hotkeyTapCallback: CGEventTapCallBack = { _, _, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let hotkey = Unmanaged<Hotkey>.fromOpaque(refcon).takeUnretainedValue()
    // The tap source lives on the main run loop, so this is the main thread.
    MainActor.assumeIsolated { hotkey.handleTap(event) }
    return Unmanaged.passUnretained(event)
}
