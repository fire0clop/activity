import CoreLocation
import MapKit
import SwiftUI

struct FeedView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = FeedViewModel()
    @StateObject private var location = LocationManager()
    @State private var isMap = false
    @State private var selected: EventListItem?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showCityPicker = false
    @State private var showSubscriptions = false

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.paper.ignoresSafeArea()
                if isMap { mapView } else { feed }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selected) { EventDetailView(eventID: $0.id) }
            .task {
                vm.configure(auth.api)
                location.request()
                if vm.items.isEmpty { await vm.refresh() }
            }
            .onReceive(location.$coordinate.compactMap { $0 }) { c in
                vm.setCoordinate(lat: c.latitude, lng: c.longitude)
                Task { await vm.refresh() }
            }
            .onReceive(location.$denied) { denied in
                // Геолокация запрещена и город не выбран — предлагаем выбрать вручную.
                if denied, vm.manualCity == nil { showCityPicker = true }
            }
            .sheet(isPresented: $showSubscriptions) {
                SubscriptionsView(latitude: vm.latitude, longitude: vm.longitude,
                                  locationName: vm.manualCity?.name ?? "моя точка")
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(selected: vm.manualCity, locationDenied: location.denied) { city in
                    vm.selectCity(city)
                    if city == nil { location.request() }
                }
            }
        }
    }

    // MARK: - Feed (bento)

    private var feed: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchAndChips
                if vm.items.isEmpty && vm.isLoading {
                    VStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                    }
                    .padding(.top, 4)
                } else if let err = vm.errorText, vm.items.isEmpty {
                    ErrorState(subtitle: err) { Task { await vm.refresh() } }
                } else if vm.items.isEmpty {
                    emptyState
                } else {
                    ForEach(sections, id: \.title) { section in
                        sectionView(section)
                    }
                    Color.clear.frame(height: 8)
                        .task { if let last = vm.items.last { await vm.loadMoreIfNeeded(current: last) } }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .refreshable { await vm.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Button { showCityPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .heavy))
                        Text(vm.manualCity?.name.uppercased() ?? "СОБЫТИЯ РЯДОМ")
                            .font(.system(size: 12, weight: .heavy)).tracking(1.5)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(Theme.accentInk)
                }
                .accessibilityLabel("Город: \(vm.manualCity?.name ?? "моё местоположение")")
                .accessibilityHint("Выбрать другой город")
                Text("Чем займёмся?").font(.display(34)).foregroundStyle(Theme.ink)
            }
            Spacer()
            HStack(spacing: 8) {
                circleButton("bell") { showSubscriptions = true }
                    .accessibilityLabel("Подписки на события")
                circleButton(isMap ? "list.bullet" : "map") { isMap.toggle() }
                    .accessibilityLabel(isMap ? "Показать списком" : "Показать на карте")
                NavigationLink { EventCreateView() } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white).frame(width: 44, height: 44)
                        .background(Theme.accent).clipShape(Circle())
                }
                .accessibilityLabel("Создать событие")
            }
        }
    }

    private func circleButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44).background(Theme.surface).clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
    }

    private var searchAndChips: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                TextField("Гидроциклы, теннис, концерт…", text: $vm.query)
                    .autocorrectionDisabled().onSubmit { Task { await vm.refresh() } }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface).clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Сегодня", "today"); chip("Завтра", "tomorrow"); chip("Выходные", "weekend")
                }
            }
        }
    }

    private func chip(_ title: String, _ value: String) -> some View {
        let active = vm.when == value
        return Button { vm.setWhen(value) } label: {
            Text(title).font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(active ? Theme.ink : Theme.surface)
                .foregroundStyle(active ? Color.white : Theme.ink)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : Theme.line, lineWidth: 1))
        }
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
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
            Map(position: $camera) {
                UserAnnotation()
                ForEach(vm.items) { item in
                    Annotation(item.title, coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)) {
                        Button { selected = item } label: {
                            let c = Categories.of(item.category)
                            Image(systemName: c.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 34, height: 34).background(c.color).clipShape(Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 2)
                        }
                    }
                }
            }
            .mapControls { MapUserLocationButton() }
        }
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
                        if let p = item.price, p > 0 { meta("rublesign", "\(Int(p))") }
                        Spacer()
                        RatingView(value: item.organizer.ratingAvg, count: 0)
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
    Group {
        if let first = item.images.first, let url = URL(string: first) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { CategoryCover(category: item.category) }
        } else {
            CategoryCover(category: item.category)
        }
    }
    .frame(height: height).frame(maxWidth: .infinity).clipped()
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
