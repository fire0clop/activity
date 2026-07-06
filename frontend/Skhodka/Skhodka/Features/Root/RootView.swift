import SwiftUI

/// Корневой экран: переключает поток по состоянию сессии.
struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ZStack { Theme.paper.ignoresSafeArea(); ProgressView().tint(Theme.accent) }
            case .signedOut:
                LoginView()
            case .onboarding:
                OnboardingView()
            case .signedIn:
                MainTabView()
            case .offline:
                OfflineView { await auth.retry() }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.light)
    }
}

/// Сессия жива, но бэк/сеть недоступны — предлагаем повторить, не разлогинивая.
struct OfflineView: View {
    var retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash").font(.system(size: 44)).foregroundStyle(Theme.ink2)
                Text("Нет соединения").font(.serifTitle(22)).foregroundStyle(Theme.ink)
                Text("Не удалось связаться с сервером. Проверьте интернет и попробуйте снова.")
                    .font(.subheadline).foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                Button {
                    Task { isRetrying = true; await retry(); isRetrying = false }
                } label: {
                    Text(isRetrying ? "Проверяем…" : "Повторить")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: 220, minHeight: 48)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isRetrying)
            }
        }
    }
}

/// Основная навигация после входа.
struct MainTabView: View {
    @ObservedObject private var push = PushCenter.shared

    init() {
        // «Бумажный» таб-бар вместо системного.
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor(Theme.surface)
        a.shadowColor = UIColor(Theme.line)
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Лента", systemImage: "square.grid.2x2.fill") }
            ChatsListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
            MyProfileView()
                .tabItem { Label("Профиль", systemImage: "person.fill") }
        }
        .tint(Theme.accent)
        // Deep-link из нажатого пуша: событие или чат поверх текущего таба.
        .sheet(item: $push.pendingRoute) { route in
            NavigationStack {
                switch route {
                case .event(let id):
                    EventDetailView(eventID: id)
                case .conversation(let id):
                    ChatView(conversationID: id, title: "Чат")
                }
            }
        }
    }
}
