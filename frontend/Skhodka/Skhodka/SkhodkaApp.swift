import SwiftUI

@main
struct SkhodkaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task { await auth.bootstrap() }
                // Ссылка вида https://event-serv.ru/e/<id> из мессенджера открывает
                // приложение сразу на событии, минуя браузер.
                .onOpenURL { url in PushCenter.shared.openUniversalLink(url) }
                .task { await claimPendingDeeplink() }
        }
    }

    /// Отложенный переход: App Store не передаёт исходную ссылку свежепоставленному
    /// приложению, поэтому спрашиваем сервер, был ли недавно переход с этого устройства.
    /// Совпадение приблизительное (адрес сети + браузер), поэтому это дополнение к
    /// обычной ссылке, а не замена: не сработало — достаточно нажать её ещё раз.
    private func claimPendingDeeplink() async {
        // Спрашиваем только с готовой сессией: до входа показывать событие всё равно негде.
        guard case .signedIn = auth.state else { return }
        guard let resp: PendingDeeplinkResponse = try? await auth.api.send(
            Endpoint(path: "/deeplinks/pending")), let id = resp.eventID else { return }
        PushCenter.shared.pendingRoute = .event(id: id)
    }
}
