import Foundation

/// Внутреннее оповещение «пользователь заблокирован».
///
/// App Store 1.2 требует, чтобы контент заблокированного исчезал из ленты
/// мгновенно. Сервер отфильтрует его при следующем запросе, но открытые
/// экраны держат старые данные в памяти — им нужно сказать об этом сразу.
extension Notification.Name {
    static let userBlocked = Notification.Name("elva.userBlocked")
}

enum UserBlocked {
    static let userIDKey = "userID"

    static func post(userID: String) {
        NotificationCenter.default.post(name: .userBlocked, object: nil,
                                        userInfo: [userIDKey: userID])
    }

    static func userID(from note: Notification) -> String? {
        note.userInfo?[userIDKey] as? String
    }
}
