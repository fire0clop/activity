import CoreLocation
import SwiftUI

/// Афиша: что вообще идёт в городе.
///
/// Раздел решает две задачи сразу. Первая — городу есть что показать, пока
/// собственных событий мало: пустая лента убивает приложение на старте. Вторая, и
/// более важная: афиша даёт повод. Человек видит концерт и собирает под него
/// компанию — так чужое мероприятие втягивается в основной цикл продукта.
struct PosterFeedView: View {
    let coordinate: CLLocationCoordinate2D
    /// Переход на страницу активностей: пустая афиша не должна быть тупиком.
    var onGoToActivities: () -> Void = {}

    @EnvironmentObject var auth: AuthManager
    @State private var items: [PosterItem] = []
    @State private var category = ""
    @State private var query = ""
    /// nil — без ограничения по датам.
    @State private var when: String?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selected: PosterItem?

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: FeedLayout.block) {
                // Фильтры — один смысловой блок, внутри плотнее, чем между блоками.
                VStack(spacing: FeedLayout.cardGap) {
                    searchField
                    whenChips
                    CategoryPicker(selection: $category)
                }

                if isLoading && items.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                } else if loadFailed {
                    ErrorState { Task { await load() } }
                } else if items.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: FeedLayout.cardGap) {
                        ForEach(items) { card($0) }
                    }
                }
            }
            .padding(.horizontal, FeedLayout.gutter)
            .padding(.top, FeedLayout.top)
            .padding(.bottom, FeedLayout.bottom)
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: category) { Task { await load() } }
        .onChange(of: when) { Task { await load() } }
        .onSubmit { Task { await load() } }
        .navigationDestination(item: $selected) { PosterDetailView(item: $0) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasFilters {
            EmptyState(
                icon: "line.3.horizontal.decrease.circle",
                title: "Ничего не нашлось",
                subtitle: "Слишком узкий срез — снимите фильтры и посмотрите всё, что идёт рядом.",
                actionTitle: "Сбросить фильтры",
                action: {
                    category = ""; when = nil; query = ""
                    Haptics.tap(); Task { await load() }
                }
            )
        } else {
            EmptyState(
                icon: "ticket",
                title: "Афиша пока пустая",
                subtitle: "Здесь будут концерты, выставки и фестивали поблизости. А пока посмотрите, что собирают люди.",
                actionTitle: "К активностям",
                action: { Haptics.tap(); onGoToActivities() }
            )
        }
    }

    private var hasFilters: Bool {
        !category.isEmpty || when != nil
            || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
            TextField("Концерт, выставка, площадка…", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await load() }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.line))
    }

    /// Даты: те же срезы, что и в ленте активностей, плюс «на неделе» —
    /// у афиши горизонт планирования длиннее, чем у спонтанной встречи.
    private var whenChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.whenOptions, id: \.value) { option in
                    let active = when == option.value
                    Button {
                        when = active ? nil : option.value
                        Haptics.tap()
                    } label: {
                        Text(option.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(active ? .white : Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(active ? Theme.ink : Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(active ? .clear : Theme.line))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1).padding(.vertical, 3)
        }
        .frame(height: CategoryPicker.rowHeight)
    }

    private static let whenOptions: [(title: String, value: String)] = [
        ("Сегодня", "today"), ("Завтра", "tomorrow"),
        ("Выходные", "weekend"), ("На неделе", "week"),
    ]

    private func card(_ p: PosterItem) -> some View {
        Button { selected = p } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Запасная обложка обязательна: смешанный список из карточек с фото
                // и без него рвёт ритм сильнее любого отступа.
                Group {
                    if let url = p.imageURL, let u = URL(string: url) {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() }
                            placeholder: { CategoryCover(category: p.category) }
                    } else {
                        CategoryCover(category: p.category)
                    }
                }
                .frame(height: 150).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CategoryBadge(category: p.category, style: .tinted)
                        Text(DateFormat.prettyDay(String(p.startsAt.prefix(10))))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        if let d = p.distanceKm {
                            Text(String(format: "%.0f км", d))
                                .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                        }
                    }
                    Text(p.title).font(.serifTitle(19, weight: .bold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let venue = p.venue {
                        Text(venue).font(.system(size: 13)).foregroundStyle(Theme.ink2).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        Text(priceLabel(p))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        // Главный сигнал: сюда уже кто-то собирается.
                        if p.gatheringsCount > 0 {
                            Label("\(p.gatheringsCount) компан\(p.gatheringsCount == 1 ? "ия" : "ии")",
                                  systemImage: "person.2.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(CardButtonStyle())
    }

    private func priceLabel(_ p: PosterItem) -> String {
        if p.isFree { return "Вход свободный" }
        guard let from = p.priceFrom, from > 0 else { return "Цена уточняется" }
        return "от \(Pricing.amount(from))"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var params = ["lat": "\(coordinate.latitude)", "lng": "\(coordinate.longitude)",
                      "radius_km": "50"]
        if !category.isEmpty { params["category"] = category }
        if let when { params["when"] = when }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { params["query"] = text }
        do {
            let resp: PosterResponse = try await auth.api.send(
                Endpoint(path: "/poster", query: params))
            items = resp.items
            loadFailed = false
        } catch {
            loadFailed = items.isEmpty
        }
    }
}

/// Карточка мероприятия из афиши.
struct PosterDetailView: View {
    let item: PosterItem
    @EnvironmentObject var auth: AuthManager
    @State private var showGather = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let url = item.imageURL, let u = URL(string: url) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.secondaryBg }
                        .frame(height: 220).frame(maxWidth: .infinity).clipped()
                }
                VStack(alignment: .leading, spacing: 14) {
                    CategoryBadge(category: item.category)
                    Text(item.title).font(.display(26)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    infoRow("calendar", DateFormat.prettyDateTime(item.startsAt))
                    if let venue = item.venue { infoRow("mappin.and.ellipse", venue) }
                    if let address = item.address { infoRow("map", address) }
                    infoRow("rublesign.circle", item.isFree
                            ? "Вход свободный"
                            : item.priceFrom.map { "от \(Pricing.amount($0))" } ?? "Цена уточняется")

                    if let d = item.description, !d.isEmpty {
                        Text(d).font(.system(size: 16)).foregroundStyle(Theme.ink.opacity(0.85))
                            .lineSpacing(3)
                    }

                    // Ради этой кнопки раздел и существует: афиша даёт повод собраться.
                    Button { showGather = true } label: {
                        Text("Собрать компанию")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Radii.sm))
                    }
                    Text(item.gatheringsCount > 0
                         ? "Уже собираются: \(item.gatheringsCount). Можно присоединиться к ним в ленте."
                         : "Никто ещё не позвал компанию — будете первым.")
                        .font(.footnote).foregroundStyle(Theme.ink2)

                    if let src = item.sourceURL, let u = URL(string: src) {
                        Link(destination: u) {
                            Label(item.sourceName.map { "Билеты · \($0)" } ?? "Купить билет",
                                  systemImage: "arrow.up.right.square")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Афиша")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGather) {
            NavigationStack {
                EventCreateView(prefill: EventCreateView.Prefill(
                    title: item.title,
                    category: item.category,
                    coordinate: CLLocationCoordinate2D(latitude: item.latitude,
                                                       longitude: item.longitude),
                    address: item.venue ?? item.address,
                    startsAt: DateFormat.parse(item.startsAt),
                    posterID: item.id
                ))
            }
        }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
