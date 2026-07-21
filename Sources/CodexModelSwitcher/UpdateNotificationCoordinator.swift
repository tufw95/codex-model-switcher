import CodexModelSwitcherCore
import Foundation
import UserNotifications

final class UpdateNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = UpdateNotificationCoordinator()

    static let categoryIdentifier = "CODEX_SWITCH_UPDATE"
    static let updateNowActionIdentifier = "CODEX_SWITCH_UPDATE_NOW"
    static let remindLaterActionIdentifier = "CODEX_SWITCH_REMIND_LATER"
    static let pendingInstallKey = "pendingUpdateInstallRequest"

    private static let snoozedVersionKey = "snoozedUpdateVersion"
    private static let snoozedUntilKey = "snoozedUpdateUntil"
    private static let reminderDelay: TimeInterval = 4 * 60 * 60

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let updateNow = UNNotificationAction(
            identifier: Self.updateNowActionIdentifier,
            title: "Update Now",
            options: [.foreground]
        )
        let remindLater = UNNotificationAction(
            identifier: Self.remindLaterActionIdentifier,
            title: "Remind Me Later"
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [updateNow, remindLater],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func postUpdateNotification(for manifest: UpdateManifest) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return false
        }
        let request = UNNotificationRequest(
            identifier: "codex-model-switcher-update-\(manifest.version)",
            content: content(version: manifest.version, message: manifest.message),
            trigger: nil
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func remindLater(version: String, message: String?) {
        Self.setSnooze(version: version)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.reminderDelay,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "codex-model-switcher-reminder-\(version)",
            content: content(version: version, message: message),
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func isSnoozed(version: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.snoozedVersionKey) == version,
              let until = defaults.object(forKey: Self.snoozedUntilKey) as? Date else {
            return false
        }
        if until > Date() {
            return true
        }
        clearSnooze()
        return false
    }

    func clearSnooze() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.snoozedVersionKey)
        defaults.removeObject(forKey: Self.snoozedUntilKey)
    }

    private func content(version: String, message: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Codex Model Switcher \(version)"
        content.body = message ?? "A new version is ready to install."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "version": version,
            "message": message ?? "A new version is ready to install.",
        ]
        return content
    }

    private static func setSnooze(version: String) {
        let defaults = UserDefaults.standard
        defaults.set(version, forKey: snoozedVersionKey)
        defaults.set(Date().addingTimeInterval(reminderDelay), forKey: snoozedUntilKey)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let version = userInfo["version"] as? String ?? "latest"
        let message = userInfo["message"] as? String

        switch response.actionIdentifier {
        case Self.updateNowActionIdentifier:
            clearSnooze()
            UserDefaults.standard.set(true, forKey: Self.pendingInstallKey)
        case Self.remindLaterActionIdentifier:
            remindLater(version: version, message: message)
        default:
            break
        }
        completionHandler()
    }
}
