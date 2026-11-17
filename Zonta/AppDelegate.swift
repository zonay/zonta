import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item. Clicking it opens the settings window, so there is
/// no popup menu in between.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var wavePhase: CGFloat = 0
    private var waveTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuIcon.image(for: .idle)
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let model = AppModel.shared
        model.boot()
        model.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.updateIcon(for: phase) }
            .store(in: &cancellables)
        installEscapeHandling()
    }

    /// Esc closes the floating speech panel, whether it has focus or the user
    /// is working in another app.
    private func installEscapeHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // 53 = Escape
            MainActor.assumeIsolated { Self.closeFloatingPanels() }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { Self.closeFloatingPanels() }
        }
    }

    @MainActor
    private static func closeFloatingPanels() {
        if SpeechPanelWindow.shared.isVisible { SpeechPanelWindow.shared.hide() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        waveTask?.cancel()
        AppLog.shared.info("Zonta terminated", subsystem: "App")
    }

    @objc private func statusClicked() {
        // Left click keeps the old behaviour. Right click opens a small menu
        // so the debug log is reachable without going through Settings.
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            for (title, action) in [
                ("Speech", #selector(openSpeech)),
                ("App Log", #selector(openLog)),
                ("Settings", #selector(openSettings)),
            ] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            let speechItem = NSMenuItem(
                title: AppModel.shared.speechEnabled ? "Disable Speech" : "Enable Speech",
                action: #selector(toggleSpeech), keyEquivalent: ""
            )
            speechItem.target = self
            menu.addItem(speechItem)
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit Zonta", action: #selector(quit), keyEquivalent: "")
            quitItem.target = self
            menu.addItem(quitItem)
            if let button = statusItem?.button {
                NSMenu.popUpContextMenu(menu, with: event, for: button)
            }
            return
        }
        SettingsWindow.toggle(model: AppModel.shared)
    }

    @objc private func openSpeech() {
        SpeechPanelWindow.shared.show(model: AppModel.shared)
    }
    @objc private func openLog() { AppLogWindow.show() }
    @objc private func openSettings() { SettingsWindow.show(model: AppModel.shared) }
    @objc private func toggleSpeech() {
        let model = AppModel.shared
        model.setSpeechEnabled(!model.speechEnabled)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateIcon(for phase: Phase) {
        statusItem?.button?.image = MenuIcon.image(for: phase, wavePhase: wavePhase)
        if phase.isAnimating {
            startWave()
        } else {
            stopWave()
        }
    }

    /// Ripple the mark while the models are working.
    private func startWave() {
        guard waveTask == nil else { return }
        waveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
                guard let self, !Task.isCancelled else { break }
                self.wavePhase += 0.45
                self.statusItem?.button?.image = MenuIcon.image(
                    for: AppModel.shared.phase,
                    wavePhase: self.wavePhase
                )
            }
        }
    }

    private func stopWave() {
        waveTask?.cancel()
        waveTask = nil
    }
}
