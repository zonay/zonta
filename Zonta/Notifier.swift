import Foundation
import UserNotifications

/// Local notifications for changes that happen straight from the keyboard,
/// with no window in front of the user.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Call once at launch. The system permission prompt appears on first run.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            Task { @MainActor in
                AppLog.shared.info(
                    "Notification status: \(settings.authorizationStatus.rawValue)",
                    subsystem: "Permissions"
                )
            }
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    AppLog.shared.warning(
                        "Notification authorization failed: \(error.localizedDescription)",
                        subsystem: "Notify"
                    )
                } else if !granted {
                    AppLog.shared.warning(
                        "Notifications are disabled — new-context alerts will not show.",
                        subsystem: "Notify"
                    )
                }
            }
        }
    }

    /// Deliver a banner immediately (a nil trigger means "now"). The in-app
    /// toast always shows; the system notification is best-effort because its
    /// authorization can be denied with no prompt for local builds.
    func post(title: String, body: String) {
        ToastWindow.shared.show(title: title, message: body)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "zonta.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in
                    AppLog.shared.warning(
                        "Notification failed: \(error.localizedDescription)",
                        subsystem: "Notify"
                    )
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Zonta can be frontmost when a hotkey fires; show the banner anyway
        // instead of letting the system swallow it.
        completionHandler([.banner, .sound])
    }
}
