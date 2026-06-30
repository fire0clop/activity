import UIKit
import UserNotifications

/// Связывает APNs-токен устройства с регистрацией на бэкенде (POST /devices).
final class PushCenter {
    static let shared = PushCenter()
    private(set) var apnsToken: String?

    /// Устанавливается AuthManager: как зарегистрировать токен на бэке.
    var onToken: ((String) -> Void)?

    /// Запрашивает разрешение и регистрирует устройство в APNs.
    func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Вызывается из AppDelegate, когда APNs выдал токен.
    func didRegister(token: String) {
        apnsToken = token
        onToken?(token)
    }
}
