import BackgroundTasks
import UIKit
import UserNotifications

/// Detects the official Instagram app and nags the user to delete it.
///
/// Detection asks iOS whether the `instagram://` scheme can be opened, which
/// needs `instagram` in LSApplicationQueriesSchemes (Info.plist). Reminders
/// are local notifications: on leaving I4A, and from the periodic background
/// refresh, which iOS runs at its own discretion.
enum InstagramApp {
    static let refreshTaskID = "com.esleoseo.i4a.refresh"
    static let alertTitle = "인스타그램 앱을 삭제하세요"
    static let alertMessage = "이 기기에 인스타그램 앱이 설치되어 있어요. 인스타그램은 I4A로만 쓰고, 원래 앱은 삭제해 주세요."

    private static let reminderID = "i4a.instagram-installed"
    private static let lastNotifiedKey = "reminder.lastNotified"
    /// Background checks notify at most this often.
    private static let notifyInterval: TimeInterval = 3 * 3600
    /// Delay of the reminder scheduled when leaving the app.
    private static let leaveReminderDelay: TimeInterval = 30 * 60

    static var isInstalled: Bool {
        guard let url = URL(string: "instagram://app") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Leaving I4A while Instagram is still installed: remind in a while,
    /// and make sure the background check gets scheduled.
    static func appDidEnterBackground() {
        scheduleBackgroundRefresh()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard isInstalled else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: leaveReminderDelay, repeats: false)
        center.add(UNNotificationRequest(identifier: reminderID, content: content(), trigger: trigger))
    }

    /// Back in I4A: the in-app alert takes over from pending reminders.
    static func appDidBecomeActive() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background refresh: check, remind, report to the admin.
    static func runBackgroundCheck() async {
        scheduleBackgroundRefresh()
        let installed = await MainActor.run { isInstalled }
        let center = UNUserNotificationCenter.current()
        if installed {
            let defaults = UserDefaults.standard
            let last = defaults.object(forKey: lastNotifiedKey) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) >= notifyInterval {
                defaults.set(Date(), forKey: lastNotifiedKey)
                try? await center.add(UNNotificationRequest(identifier: reminderID, content: content(), trigger: nil))
            }
        } else {
            // Deleted since the reminder was scheduled.
            center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        }
        let usage = UsageTracker.storedUsage()
        await withCheckedContinuation { continuation in
            AdminSync.sendReport(usedSeconds: usage.seconds, day: usage.day, instagramInstalled: installed) {
                continuation.resume()
            }
        }
    }

    private static func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alertTitle
        content.body = alertMessage
        content.sound = .default
        return content
    }
}
