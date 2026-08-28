import UserNotifications

/// Minimal user-visible feedback for failures, per spec §11: "never lose a
/// capture silently; always tell the user why something failed." This is a
/// stopgap ahead of the real capture toast (build order step 11) — a failed
/// resolve or capture should never be invisible the way it was before this
/// existed.
enum NotificationService {
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert]) { granted, error in
                if let error {
                    Log.app.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    Log.app.info("notification authorization: \(granted, privacy: .public)")
                }
            }
        }
    }

    static func notifyFailure(title: String, body: String) {
        Log.app.error("\(title, privacy: .public): \(body, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
