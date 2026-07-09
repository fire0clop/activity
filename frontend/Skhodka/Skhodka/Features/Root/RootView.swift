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
                signedOutRoot
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

    @ViewBuilder
    private var signedOutRoot: some View {
        #if DEBUG
        // Headless-скриншоты регистрации: UITEST_ROUTE начинается с "register".
        if ProcessInfo.processInfo.environment["UITEST_ROUTE"]?.hasPrefix("register") == true {
            NavigationStack { RegisterView() }
        } else {
            LoginView()
        }
        #else
        LoginView()
        #endif
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

    @State private var tab = 0
    @State private var showCreate = false

    var body: some View {
        TabView(selection: $tab) {
            FeedView()
                .tabItem { Label("Лента", systemImage: "square.grid.2x2.fill") }.tag(0)
            ChatsListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }.tag(1)
            MyProfileView()
                .tabItem { Label("Профиль", systemImage: "person.fill") }.tag(2)
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
        .sheet(isPresented: $showCreate) { NavigationStack { EventCreateView() } }
        .onAppear(perform: applyUITestRoute)
    }

    /// DEBUG-only: переход на нужный экран по переменной окружения запуска — для headless
    /// снятия скриншотов (никакого управления мышью). В релиз не попадает.
    private func applyUITestRoute() {
        #if DEBUG
        guard let route = ProcessInfo.processInfo.environment["UITEST_ROUTE"] else { return }
        if route == "profile" { tab = 2 }
        else if route == "chats" { tab = 1 }
        else if route == "create" { showCreate = true }
        else if route.hasPrefix("event:") { push.pendingRoute = .event(id: String(route.dropFirst(6))) }
        else if route.hasPrefix("chat:") { push.pendingRoute = .conversation(id: String(route.dropFirst(5))) }
        #endif
    }
}
