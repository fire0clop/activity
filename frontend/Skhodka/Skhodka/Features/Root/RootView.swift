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
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.light)
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
