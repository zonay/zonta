import AppKit
import SwiftUI

/// A short-lived banner that needs no permission. macOS notification
/// authorization can be blocked for locally built apps, so this is the
/// always-works half of `Notifier.post`.
@MainActor
final class ToastWindow {
    static let shared = ToastWindow()

    private var window: NSWindow?
    private var hideTask: Task<Void, Never>?

    func show(title: String, message: String, seconds: Double = 4) {
        hideTask?.cancel()
        let host = NSHostingController(
            rootView: ToastView(title: title, message: message)
        )
        if let window {
            window.contentViewController = host
            Self.place(window)
            window.orderFront(nil)
        } else {
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.borderless]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.isExcludedFromWindowsMenu = true
            window.setContentSize(Self.size)
            Self.place(window)
            self.window = window
            window.orderFront(nil)
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.window?.orderOut(nil)
        }
    }

    fileprivate static let size = NSSize(width: 320, height: 84)

    private static func place(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 24
        ))
    }
}

private struct ToastView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: ToastWindow.size.width, height: ToastWindow.size.height, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
