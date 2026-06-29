import Foundation
import UserNotifications

public final class NotificationService {
    public init() {}

    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    public func notify(flag: AlertFlag) async {
        let content = UNMutableNotificationContent()
        content.title = "GSMTools Alert"
        content.body = flag.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: flag.id.uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
