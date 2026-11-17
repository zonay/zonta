import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Hold-to-talk for the modifiers that are not already busy typing.
///
/// - Globe (fn) is the voice chat.
/// - Right Command is dictation.
/// - Right Option is translation.
///
/// A modifier only counts as a hold when it is pressed for a moment and no
/// other key follows. Option in particular is how accented characters are
/// typed, so Option+e must never start a recording. A session event tap
/// catches that other key and cancels the pending start.
@MainActor
final class Hotkey {
    var onGlobeDown: (() -> Void)?
    var onGlobeUp: (() -> Void)?
    var onRightCommandDown: (() -> Void)?
    var onRightCommandUp: (() -> Void)?
    var onRightCommandCancel: (() -> Void)?
    var onRightOptionDown: (() -> Void)?
    var onRightOptionUp: (() -> Void)?
    var onRightOptionCancel: (() -> Void)?

    private enum Side { case command, option }

    private var monitor: Any?
    private var global: Any?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var globeHeld = false
    private var pending: Side?
    private var active: Side?
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
        globeHeld = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        let globe = event.modifierFlags.contains(.function)
        if globe != globeHeld {
            globeHeld = globe
            if globe { onGlobeDown?() } else { onGlobeUp?() }
        }

        let side: Side
        switch event.keyCode {
        case UInt16(kVK_RightCommand): side = .command
        case UInt16(kVK_RightOption): side = .option
        default: return
        }

        let pressed: Bool
        switch side {
        case .command: pressed = event.modifierFlags.contains(.command)
        case .option: pressed = event.modifierFlags.contains(.option)
        }

        if pressed {
            if active != side { beginHold(side) }
        } else {
            release(side)
        }
    }

    fileprivate func handleTap(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(CGEventField.keyboardEventKeycode))
        guard !Self.modifierKeyCodes.contains(keyCode) else { return }
        // Another key went down while a modifier was held. That is a shortcut,
        // not dictation.
        if pending != nil {
            cancelPending()
        } else if active != nil {
            abort()
        }
    }

    // MARK: - Hold state

    private func beginHold(_ side: Side) {
        pendingTask?.cancel()
        pending = side
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Hotkey.holdDelay)
            guard let self, !Task.isCancelled, self.pending == side, self.active == nil else { return }
            self.pending = nil
            self.active = side
            switch side {
            case .command: self.onRightCommandDown?()
            case .option: self.onRightOptionDown?()
            }
        }
    }

    private func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
    }

    private func release(_ side: Side) {
        cancelPending()
        guard active == side else { return }
        active = nil
        switch side {
        case .command: onRightCommandUp?()
        case .option: onRightOptionUp?()
        }
    }

    private func abort() {
        cancelPending()
        guard let side = active else { return }
        active = nil
        switch side {
        case .command: onRightCommandCancel?()
        case .option: onRightOptionCancel?()
        }
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
