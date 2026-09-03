import SwiftUI

/// Корневой экран: переключает поток по состоянию сессии.
struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    /// Версия правил, с которой человек согласился. Пустая — согласия не было.
    @AppStorage(Terms.storageKey) private var tosAccepted = ""

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
        // Правила показываются до регистрации и входа (App Store 1.2):
        // без согласия дальше этого экрана не попасть.
        if tosAccepted != Terms.version {
            TermsGateView { tosAccepted = Terms.version }
        } else {
            authRoot
        }
    }

    @ViewBuilder
    private var authRoot: some View {
        #if DEBUG
        // Headless-скриншоты регистрации: UITEST_ROUTE начинается с "register".
        if ProcessInfo.processInfo.environment["UITEST_ROUTE"]?.hasPrefix("register") == true {
            NavigationStack { RegisterView() }
        } else if ProcessInfo.processInfo.environment["UITEST_ROUTE"]?.hasPrefix("reset") == true {
            NavigationStack { PasswordResetView() }
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

    /// Обучение показывает именно этот контейнер, а не сама лента: подсветка должна
    /// накрывать и таб-бар. Изнутри вкладки он остаётся сверху — кнопки обучения
    /// оказывались под ним, не нажимались, а тап переключал вкладку.
    @StateObject private var tour = TourController(steps: FeedTour.steps,
                                                   storageKey: FeedTour.storageKey)
    /// Сброс из профиля подхватываем сразу, не дожидаясь пересоздания экрана.
    @AppStorage(FeedTour.storageKey) private var tourSeen = false

    var body: some View {
        TabView(selection: $tab) {
            FeedView(tourActive: tour.isActive)
                .tabItem { Label("Лента", systemImage: "square.grid.2x2.fill") }.tag(0)
            ChatsListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }.tag(1)
            MyProfileView()
                .tabItem { Label("Профиль", systemImage: "person.fill") }.tag(2)
        }
        .tint(Theme.accent)
        .tour(tour)
        // Обучение не ждёт загрузки данных: шапка и переключатель разделов на экране
        // сразу, объяснять есть что.
        .onAppear(perform: startTourIfOnFeed)
        // Сброс из профиля происходит на другой вкладке, поэтому одного отклика на
        // отметку мало: без реакции на смену вкладки «Как это работает» показывало
        // сообщение, а на ленте потом ничего не появлялось.
        .onChange(of: tab) { _, _ in startTourIfOnFeed() }
        .onChange(of: tourSeen) { _, _ in startTourIfOnFeed() }
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

    /// Обучение живёт на ленте: на других вкладках его шаги не про что.
    private func startTourIfOnFeed() {
        guard tab == 0 else { return }
        tour.startIfNeeded()
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
