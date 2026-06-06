import Foundation
import UserNotifications

// MARK: - Local notifications
// Fires a local notification when a scan finds devices that weren't on the
// network before. Permission is requested lazily the first time we'd notify.
// A delegate allows the banner to show even while the app is in the foreground
// (scans run with the app open, so without this the alert would never appear).

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    @Published var authorized = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorized = granted
        case .authorized, .provisional, .ephemeral:
            authorized = true
        default:
            authorized = false
        }
    }

    func notifyNewDevices(count: Int, networkName: String) async {
        await requestAuthorizationIfNeeded()
        guard authorized, count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "New device on your network" : "\(count) new devices on your network"
        content.body = "\(AppInfo.displayName) spotted \(count == 1 ? "a device" : "devices") on \(networkName) not seen in earlier scans."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Allow banners + sound while the app is in the foreground.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
