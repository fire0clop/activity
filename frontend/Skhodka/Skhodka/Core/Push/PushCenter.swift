import UIKit
import UserNotifications

/// Куда вести пользователя по нажатию на пуш.
enum PushRoute: Identifiable, Equatable {
    case event(id: String)
    case conversation(id: String)

    var id: String {
        switch self {
        case .event(let id): return "event-\(id)"
        case .conversation(let id): return "conversation-\(id)"
        }
    }

    /// Из data-полей пуша (бэк кладёт event_id / conversation_id).
    static func from(userInfo: [AnyHashable: Any]) -> PushRoute? {
        if let cid = userInfo["conversation_id"] as? String { return .conversation(id: cid) }
        if let eid = userInfo["event_id"] as? String { return .event(id: eid) }
        return nil
    }
}

/// Связывает APNs-токен устройства с регистрацией на бэкенде (POST /devices)
/// и передаёт deep-link из нажатого пуша в UI.
///
/// Изолирован `@MainActor`: `apnsToken`/`pendingRoute`/`onToken` читаются и пишутся
/// из UI и из APNs-колбэков — единый актор исключает гонки на этих полях.
@MainActor
final class PushCenter: ObservableObject {
    static let shared = PushCenter()
    private(set) var apnsToken: String?

    /// Маршрут из нажатого пуша; UI показывает и сбрасывает.
    @Published var pendingRoute: PushRoute?

    /// Устанавливается AuthManager: как зарегистрировать токен на бэке.
    var onToken: ((String) -> Void)?

    /// Запрашивает разрешение и регистрирует устройство в APNs.
    func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            guard granted else {
                if let error { NSLog("Push: authorization denied/failed: \(error.localizedDescription)") }
                return
            }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Вызывается из AppDelegate, когда APNs выдал токен.
    func didRegister(token: String) {
        apnsToken = token
        onToken?(token)
    }

    /// Вызывается из AppDelegate по нажатию на уведомление.
    func open(userInfo: [AnyHashable: Any]) {
        guard let route = PushRoute.from(userInfo: userInfo) else { return }
        pendingRoute = route
    }
}
