import Foundation

/// Конфигурация окружения. Значения приходят из Configs/*.xcconfig через Info.plist:
/// Debug → Dev.xcconfig (localhost для симулятора, LAN-IP для устройства),
/// Release → Prod.xcconfig (боевой домен, https/wss).
enum AppConfig {
    static let host: String = infoValue("APIHost")
    private static let apiScheme: String = infoValue("APIScheme")
    private static let wsScheme: String = infoValue("WSScheme")

    static let baseURL = URL(string: "\(apiScheme)://\(host)/api/v1")!
    static let wsBaseURL = URL(string: "\(wsScheme)://\(host)/api/v1")!

    /// Домен универсальных ссылок. Он же раздаёт apple-app-site-association, поэтому
    /// обязан совпадать с applinks-записью в Elva.entitlements.
    static let shareHost = "event-serv.ru"

    /// Ссылка на событие для мессенджеров: с приложением открывает карточку,
    /// без него уводит в App Store.
    static func shareURL(eventID: String) -> URL {
        URL(string: "https://\(shareHost)/e/\(eventID)")!
    }

    private static func infoValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            fatalError("AppConfig: ключ \(key) не задан — проверь Configs/*.xcconfig и Info.plist")
        }
        return value
    }
}

/// Правовые документы (App Store Connect требует Privacy Policy; Guideline 1.2 — правила UGC).
/// Размещены на GitHub Pages из папки docs/ репозитория.
enum Legal {
    static let privacyPolicyURL = URL(string: "https://fire0clop.github.io/activity/privacy.html")!
    static let termsURL = URL(string: "https://fire0clop.github.io/activity/terms.html")!
}
