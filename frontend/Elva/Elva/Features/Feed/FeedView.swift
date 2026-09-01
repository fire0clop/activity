import CoreLocation
import MapKit
import SwiftUI

/// Единая геометрия трёх страниц ленты.
///
/// Шапка над ними общая, поэтому любое расхождение в полях и в старте контента
/// читается как скачок при свайпе. Раньше поля были 18/16/16, а верхний отступ
/// 8/0/16 — страницы дёргались на каждом переходе.
enum FeedLayout {
    static let gutter: CGFloat = 16    // поля экрана, совпадают с шапкой
    static let top: CGFloat = 12       // одинаковая высота старта контента
    static let block: CGFloat = 16     // между смысловыми блоками
    static let cardGap: CGFloat = 12   // между карточками
    static let bottom: CGFloat = 24    // воздух под последней карточкой
}

struct FeedView: View {
    /// Идёт обучение. Его шаги объясняют кнопки первой страницы — на «Афише» и
    /// «Хочу» часть из них скрыта, и подсветка обводила пустое место.
    let tourActive: Bool

    init(tourActive: Bool = false) { self.tourActive = tourActive }

    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = FeedViewModel()
    @StateObject private var location = LocationManager()
    @State private var isMap = false
    @State private var selected: EventListItem?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showCityPicker = false
    @State private var showSubscriptions = false
    /// Активная страница ленты: 0 — активности, 1 — афиша, 2 — желания.
    @State private var page = 0
    /// Афиша на карте: подгружается отдельно от событий, показывается другой меткой.
    @State private var posterPins: [PosterItem] = []
    @State private var selectedPoster: PosterItem?
    @State private var showCreateRequest = false
    @State private var filters = FeedFilters()
    @State private var showFilters = false
    @Namespace private var pageIndicator


    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// В UI-тестах точку задаём заранее: системный запрос геопозиции и следом
    /// выбор города перехватывают экран и делают прогон нестабильным.
    private var skipLocation: Bool {
        ProcessInfo.processInfo.environment["UITEST_SKIP_LOCATION"] != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.paper.ignoresSafeArea()
                VStack(spacing: 0) {
                    header.padding(.horizontal, 16).padding(.top, 8)
                    pageSwitcher.padding(.horizontal, 16).padding(.top, 12)
                    // Три страницы листаются пальцем: активности людей — основная,
                    // афиша и желания живут рядом, а не в закопанных разделах.
                    TabView(selection: $page) {
                        activitiesPage.tag(0)
                        posterPage.tag(1)
                        RequestsView(coordinate: center,
                                     everywhere: vm.scope == .everywhere,
                                     areaHint: vm.manualCity?.name,
                                     embedded: true, showCreate: $showCreateRequest).tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.2), value: page)
                }
                // Замеряем зону вкладки без панели снизу — обучение по ней понимает,
                // докуда можно опускать пояснение, чтобы кнопки остались нажимаемыми.
                .background(Color.clear.tourAnchor(TourLayout.content))
            }
            .navigationBarHidden(true)
            .onAppear { if tourActive { page = 0 } }
            .onChange(of: tourActive) { _, active in if active { page = 0 } }
            .navigationDestination(item: $selected) { EventDetailView(eventID: $0.id) }
            .task {
                vm.configure(auth.api)
                // Разрешение спрашиваем только когда оно нужно. По умолчанию лента
                // показывает все города, и просить геопозицию на первом запуске
                // не за что — это раздражает и снижает согласие.
                if !skipLocation, vm.scope == .nearMe { location.request() }
                if vm.items.isEmpty { await vm.refresh() }
            }
            .onReceive(location.$coordinate.compactMap { $0 }) { c in
                vm.setCoordinate(lat: c.latitude, lng: c.longitude)
                Task { await vm.refresh() }
            }
            .onReceive(location.$denied) { denied in
                // Геолокация запрещена и город не выбран — предлагаем выбрать вручную.
                if denied, vm.scope == .nearMe, !skipLocation { showCityPicker = true }
            }
            .sheet(isPresented: $showSubscriptions) {
                SubscriptionsView(latitude: vm.latitude, longitude: vm.longitude,
                                  locationName: vm.manualCity?.name ?? "моя точка")
            }
            .sheet(isPresented: $showFilters) {
                FiltersSheet(filters: $filters) { applyFilters() }
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(scope: vm.scope, locationDenied: location.denied) { picked in
                    vm.select(picked)
                    // Спрашиваем доступ только когда человек сам выбрал «моё
                    // местоположение» — в остальных режимах он не нужен.
                    if picked == .nearMe { location.request() }
                }
            }
        }
    }

    /// Точка, вокруг которой смотрим все три раздела.
    private var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: vm.latitude, longitude: vm.longitude)
    }

    /// Карта общая для двух первых страниц: на ней и события людей, и афиша,
    /// поэтому переключатель списка/карты работает с обеих.
    @ViewBuilder
    private var activitiesPage: some View {
        if isMap { mapView } else { feed }
    }

    @ViewBuilder
    private var posterPage: some View {
        if isMap { mapView } else {
            PosterFeedView(coordinate: center, everywhere: vm.scope == .everywhere) { withAnimation { page = 0 } }
        }
    }

    /// Переключатель страниц. Дублирует свайп кнопками: свайп сам по себе не виден,
    /// и без подписей человек не узнает, что разделов три.
    private var pageSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.pages.enumerated()), id: \.offset) { i, item in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { page = i }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon).font(.system(size: 11, weight: .bold))
                        Text(item.title).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(page == i ? .white : Theme.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background {
                        // Один индикатор на весь трек: движение читается как
                        // «страница едет», а не как три независимые кнопки.
                        if page == i {
                            Capsule().fill(Theme.accentInk)
                                .matchedGeometryEffect(id: "page", in: pageIndicator)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == i ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.lineStrong))
        .tourAnchor("tour.pages")
    }

    /// Настроение страницы. Отдельно от названия вкладки: вкладка называет раздел.
    private static let titles = ["Чем займёмся?", "Что идёт рядом", "Кто чего хочет"]

    private static let pages: [(title: String, icon: String)] = [
        ("Активности", "square.grid.2x2.fill"),
        ("Афиша", "ticket.fill"),
        ("Хочу", "hand.raised.fill"),
    ]

    // MARK: - Feed (bento)

    private var feed: some View {
        // Поиск и фильтры — над прокруткой, а не внутри неё. Внутри они
        // перекладывались вместе с карточками при каждом обновлении списка, и
        // нажатие, пришедшее в этот момент, засчитывалось по старой геометрии:
        // вместо кнопки открывалась карточка, оказавшаяся на её месте.
        VStack(spacing: 0) {
            searchAndChips
                .padding(.horizontal, FeedLayout.gutter)
                .padding(.top, FeedLayout.top)
                .padding(.bottom, FeedLayout.cardGap)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: FeedLayout.block) {
                    if vm.items.isEmpty && vm.isLoading {
                        VStack(spacing: FeedLayout.block) {
                            ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                        }
                    } else if let err = vm.errorText, vm.items.isEmpty {
                        ErrorState(subtitle: err) { Task { await vm.refresh() } }
                    } else if vm.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(sections, id: \.title) { section in
                            sectionView(section)
                        }
                        Color.clear.frame(height: 8)
                            .task {
                                if let last = vm.items.last {
                                    await vm.loadMoreIfNeeded(current: last)
                                }
                            }
                    }
                }
                .padding(.horizontal, FeedLayout.gutter)
                .padding(.top, FeedLayout.top)
                .padding(.bottom, FeedLayout.bottom)
            }
            .refreshable { await vm.refresh() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Button { showCityPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .heavy))
                        Text(vm.scope.title.uppercased())
                            .font(.system(size: 12, weight: .heavy)).tracking(1.5)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(Theme.accentInk)
                }
                .accessibilityLabel("Показываем: \(vm.scope.title)")
                .accessibilityHint("Выбрать другой город")
                Text(Self.titles[page])
                    .font(.display(28)).foregroundStyle(Theme.ink)
                    // Заголовок общий для трёх страниц: перенос на вторую строку
                    // поднимал бы весь контент под ним.
                    .lineLimit(1).minimumScaleFactor(0.72)
                    .frame(height: 34, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: page)
            }
            Spacer()
            HStack(spacing: 8) {
                circleButton("bell") { showSubscriptions = true }
                    .accessibilityLabel("Подписки на события")
                // Место под кнопку карты держим всегда: иначе соседние кнопки
                // перескакивают на 44pt при каждом свайпе.
                circleButton(isMap ? "list.bullet" : "map") { isMap.toggle() }
                    .accessibilityLabel(isMap ? "Показать списком" : "Показать на карте")
                    .tourAnchor("tour.map")
                    .opacity(page == 2 ? 0 : 1)
                    .disabled(page == 2)
                    .accessibilityHidden(page == 2)
                // Афишу заводит оператор — там создавать нечего.
                plusButton
                    .tourAnchor("tour.create")
                    .opacity(page == 1 ? 0 : 1)
                    .disabled(page == 1)
                    .accessibilityHidden(page == 1)
            }
            .animation(.easeInOut(duration: 0.18), value: page)
        }
    }

    /// «+» меняет смысл вместе со страницей. Подменять дешёвое действие дорогим
    /// под одной иконкой нельзя: на «Хочу» человек ждёт желание, а не публикацию.
    @ViewBuilder
    private var plusButton: some View {
        if page == 2 {
            Button { showCreateRequest = true; Haptics.tap() } label: { plusIcon }
                .accessibilityLabel("Сказать, чего хочу")
        } else {
            NavigationLink { EventCreateView() } label: { plusIcon }
                .accessibilityLabel("Создать событие")
        }
    }

    private var plusIcon: some View {
        Image(systemName: "plus").font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white).frame(width: 44, height: 44)
            .background(Theme.accent).clipShape(Circle())
    }

    private func circleButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44).background(Theme.surface).clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
    }

    private var searchAndChips: some View {
        VStack(spacing: FeedLayout.cardGap) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                TextField("Гидроциклы, теннис, концерт…", text: $vm.query)
                    .autocorrectionDisabled().onSubmit { Task { await vm.refresh() } }
                if !vm.query.isEmpty {
                    Button {
                        vm.query = ""
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface).clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.lineStrong, lineWidth: 1))

            HStack(spacing: 8) {
                FiltersButton(filters: filters) { showFilters = true }
                    .tourAnchor("tour.filters")
                if !filters.isEmpty {
                    Button {
                        filters.reset(); Haptics.tap()
                        applyFilters()
                    } label: {
                        Text("Сбросить").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func applyFilters() {
        vm.setFilters(category: filters.category, when: filters.when, freeOnly: filters.freeOnly)
        Task { await vm.refresh() }
    }

    // MARK: - Sections (bento: 1 крупная + сетка)

    private struct FeedSection { let order: Int; let title: String; let items: [EventListItem] }

    private var sections: [FeedSection] {
        var buckets: [Int: (String, [EventListItem])] = [:]
        for item in vm.items {
            let (order, title) = Self.bucket(item.day)
            buckets[order, default: (title, [])].1.append(item)
        }
        return buckets.sorted { $0.key < $1.key }.map { FeedSection(order: $0.key, title: $0.value.0, items: $0.value.1) }
    }

    private static func bucket(_ dayStr: String) -> (Int, String) {
        guard let d = DateFormat.dayDate(dayStr) else { return (3, "Позже") }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: d)).day ?? 0
        if days <= 0 { return (0, "Сегодня") }
        if days == 1 { return (1, "Завтра") }
        let wd = cal.component(.weekday, from: d)
        if days <= 7 && (wd == 7 || wd == 1) { return (2, "На выходных") }
        return (3, "Позже")
    }

    @ViewBuilder
    private func sectionView(_ s: FeedSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.title).font(.serifTitle(24, weight: .bold)).foregroundStyle(Theme.ink)
                Text("\(s.items.count)").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink2)
                Spacer()
            }
            if let feature = s.items.first {
                FeatureEventCard(item: feature) { selected = feature }
            }
            // Остальное — bento: пары в 2 колонки, одиночный «хвост» — широкой карточкой.
            let rest = Array(s.items.dropFirst())
            let pairs = stride(from: 0, to: rest.count, by: 2).map { Array(rest[$0..<min($0 + 2, rest.count)]) }
            ForEach(pairs.indices, id: \.self) { i in
                let pair = pairs[i]
                if pair.count == 2 {
                    HStack(spacing: 12) {
                        BentoEventCard(item: pair[0]) { selected = pair[0] }
                        BentoEventCard(item: pair[1]) { selected = pair[1] }
                    }
                } else {
                    WideEventCard(item: pair[0]) { selected = pair[0] }
                }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("На карте").font(.display(26)).foregroundStyle(Theme.ink)
                Spacer()
                circleButton("list.bullet") { isMap = false }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)
            mapLegend.padding(.horizontal, 18).padding(.bottom, 8)
            Map(position: $camera) {
                UserAnnotation()
                // События людей — круглые метки в цвете категории.
                ForEach(vm.items) { item in
                    Annotation(item.title, coordinate: CLLocationCoordinate2D(
                        latitude: item.latitude, longitude: item.longitude)) {
                        Button { selected = item } label: {
                            let c = Categories.of(item.category)
                            Image(systemName: c.icon)
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 34, height: 34).background(c.color).clipShape(Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 2)
                        }
                    }
                }
                // Афиша — квадратная метка одного цвета: это чужие мероприятия,
                // а не чей-то сбор, и путать их на карте нельзя.
                ForEach(posterPins) { item in
                    Annotation(item.title, coordinate: CLLocationCoordinate2D(
                        latitude: item.latitude, longitude: item.longitude)) {
                        Button { selectedPoster = item } label: {
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9)
                                    .stroke(.white, lineWidth: 2))
                                .shadow(radius: 2)
                        }
                    }
                }
            }
            .mapControls { MapUserLocationButton() }
        }
        // Ключ включает точку: при смене города метки перезагружаются сами.
        .task(id: "\(isMap)-\(vm.latitude),\(vm.longitude)") {
            if isMap { await loadPosterPins() }
        }
        .navigationDestination(item: $selectedPoster) { PosterDetailView(item: $0) }
    }

    /// Легенда: без неё две разные метки читаются как случайный разнобой.
    private var mapLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 12, height: 12)
                Text("собирают люди").font(.system(size: 12)).foregroundStyle(Theme.ink2)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.ink).frame(width: 12, height: 12)
                Text("афиша").font(.system(size: 12)).foregroundStyle(Theme.ink2)
            }
            Spacer()
        }
    }

    private func loadPosterPins() async {
        let resp: PosterResponse? = try? await auth.api.send(Endpoint(
            path: "/poster",
            query: ["lat": "\(vm.latitude)", "lng": "\(vm.longitude)", "radius_km": "50"]))
        posterPins = resp?.items ?? []
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 96, height: 96)
                Image(systemName: "sparkles").font(.system(size: 38)).foregroundStyle(Theme.accent)
            }
            Text("Рядом пока тихо").font(.serifTitle(22, weight: .bold)).foregroundStyle(Theme.ink)
            Text("Стань первым — придумай движуху,\nи к тебе подтянутся.")
                .font(.subheadline).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)

            // Холодный старт: если чуть дальше есть события — предлагаем расширить радиус.
            if let radius = vm.suggestedRadiusKm, let count = vm.suggestedCount {
                VStack(spacing: 8) {
                    Text("В радиусе \(Int(radius)) км уже есть \(count) \(eventsWord(count)).")
                        .font(.footnote).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                    Button {
                        vm.expandRadius(); Haptics.tap()
                    } label: {
                        Text("Показать их").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Theme.accentSoft).clipShape(Capsule())
                    }
                }
                .padding(.top, 4)
            }

            NavigationLink { EventCreateView() } label: {
                Text("Создать событие").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 13).background(Theme.accent).clipShape(Capsule())
            }

            // Организовать готовы единицы, а сказать «хочу» — многие. В пустом городе
            // это единственный дешёвый способ показать, что тут вообще кто-то живой.
            Button { withAnimation { page = 2 } } label: {
                Text("Или скажите, чего хотите")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accentSoft).clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 50)
    }

    /// Склонение слова «событие» для чисел (1 событие, 3 события, 5 событий).
    private func eventsWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "событие" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "события" }
        return "событий"
    }
}

// MARK: - Cards

private struct FeatureEventCard: View {
    let item: EventListItem
    var onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    cover(item, height: 190)
                    HStack {
                        CategoryBadge(category: item.category)
                        Spacer()
                        dayPill(item.day)
                    }.padding(12)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title).font(.serifTitle(22, weight: .bold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 14) {
                        meta("location.fill", item.distanceKm.map { String(format: "%.1f км", $0) } ?? "—")
                        meta("person.2.fill", "\(item.participantsCurrent)/\(item.participantsMax.map(String.init) ?? "∞")")
                        // В ленте показываем то, что человек реально заплатит:
                        // для общего счёта это доля, а не вся сумма выкупа.
                        if let p = item.price, p > 0 {
                            meta("rublesign", Pricing.short(price: p, split: item.priceSplit,
                                                            current: item.participantsCurrent)
                                .replacingOccurrences(of: " ₽", with: ""))
                        }
                        Spacer()
                        // Пусто, пока об организаторе нет отзывов: в ленте «Новичок» — лишний шум.
                        RatingView(value: item.organizer.ratingAvg, count: item.organizer.reviewsCount)
                    }
                }.padding(14)
            }
            .cardStyle()
        }.buttonStyle(CardButtonStyle())
    }
}

private struct BentoEventCard: View {
    let item: EventListItem
    var onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    cover(item, height: 120)
                    CategoryBadge(category: item.category, compact: true).padding(8)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.serifTitle(16, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text(item.distanceKm.map { String(format: "%.1f км", $0) } ?? "—")
                        Text("·")
                        Text("\(item.participantsCurrent)/\(item.participantsMax.map(String.init) ?? "∞")")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink2)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .cardStyle()
        }.buttonStyle(CardButtonStyle())
    }
}

/// Широкая горизонтальная карточка — для одиночного «хвоста» секции (чтобы не висел половинкой).
private struct WideEventCard: View {
    let item: EventListItem
    var onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    cover(item, height: 110).frame(width: 120)
                    CategoryBadge(category: item.category, compact: true).padding(7)
                }
                .frame(width: 120, height: 110).clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.serifTitle(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        meta("location.fill", item.distanceKm.map { String(format: "%.1f км", $0) } ?? "—")
                        meta("person.2.fill", "\(item.participantsCurrent)/\(item.participantsMax.map(String.init) ?? "∞")")
                    }
                    HStack(spacing: 6) {
                        let p = DateFormat.dayPill(item.day)
                        Text("\(p.num) \(p.month)").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.accent)
                        Spacer()
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .cardStyle()
        }.buttonStyle(CardButtonStyle())
    }
}

@ViewBuilder
private func cover(_ item: EventListItem, height: CGFloat) -> some View {
    CoverImage(url: item.images.first, category: item.category, height: height)
}

private func meta(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 11, weight: .semibold))
        Text(text).font(.system(size: 13, weight: .semibold))
    }.foregroundStyle(Theme.ink2)
}

private func dayPill(_ day: String) -> some View {
    let p = DateFormat.dayPill(day)
    return VStack(spacing: 0) {
        Text(p.num).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
        Text(p.month).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.accent).tracking(0.5)
    }
    .frame(width: 42, height: 42).background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
}
