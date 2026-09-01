import Foundation

/// Что показывает лента.
///
/// По умолчанию — всё подряд, без привязки к городу. У молодого продукта событий
/// мало, и лента, отфильтрованная по десяти километрам вокруг, у большинства
/// оказывается пустой. Сузить до своего города или своей точки человек может сам.
enum FeedScope: Equatable {
    case everywhere
    case nearMe
    case city(City)

    var city: City? {
        if case .city(let c) = self { return c }
        return nil
    }

    var title: String {
        switch self {
        case .everywhere: return "Все города"
        case .nearMe: return "Моё местоположение"
        case .city(let c): return c.name
        }
    }
}

/// Город для ручного выбора точки ленты (когда геолокация запрещена или не нужна).
struct City: Codable, Equatable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }
}

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var items: [EventListItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    /// Холодный старт: подсказка расширить радиус, когда рядом пусто.
    @Published private(set) var suggestedRadiusKm: Double?
    @Published private(set) var suggestedCount: Int?

    // Фильтры
    @Published var when: String?        // nil | today | tomorrow | weekend | week
    @Published var category: String = ""
    @Published var freeOnly = false
    @Published var query: String = ""
    @Published var radiusKm: Double = 30

    @Published private(set) var scope: FeedScope = .everywhere

    /// Город, выбранный вручную; nil — лента не привязана к конкретному городу.
    var manualCity: City? { scope.city }

    // Координаты (по умолчанию центр Москвы, пока нет ни геолокации, ни города)
    private(set) var latitude = 55.751
    private(set) var longitude = 37.618

    private var nextCursor: String?
    private var api: APIClient?
    private let cityKey = "feed.manualCity"
    private let scopeKey = "feed.scope"

    init() {
        switch UserDefaults.standard.string(forKey: scopeKey) {
        case "nearMe":
            scope = .nearMe
        case "city":
            if let data = UserDefaults.standard.data(forKey: cityKey),
               let city = try? JSONDecoder().decode(City.self, from: data) {
                scope = .city(city)
                latitude = city.latitude
                longitude = city.longitude
            }
        default:
            break   // ничего не выбирали — показываем всё
        }
    }

    func configure(_ api: APIClient) { self.api = api }

    /// Координата от GPS. Игнорируется, если выбран конкретный город.
    ///
    /// В режиме «все города» точка всё равно нужна: от неё создаются события
    /// и желания, и по ней центрируется карта.
    func setCoordinate(lat: Double, lng: Double) {
        guard scope.city == nil else { return }
        latitude = lat
        longitude = lng
    }

    func select(_ newScope: FeedScope) {
        scope = newScope
        switch newScope {
        case .city(let city):
            latitude = city.latitude
            longitude = city.longitude
            UserDefaults.standard.set("city", forKey: scopeKey)
            if let data = try? JSONEncoder().encode(city) {
                UserDefaults.standard.set(data, forKey: cityKey)
            }
        case .nearMe:
            UserDefaults.standard.set("nearMe", forKey: scopeKey)
            UserDefaults.standard.removeObject(forKey: cityKey)
        case .everywhere:
            UserDefaults.standard.set("everywhere", forKey: scopeKey)
            UserDefaults.standard.removeObject(forKey: cityKey)
        }
        Task { await refresh() }
    }

    func setWhen(_ value: String?) {
        when = (when == value) ? nil : value
        Task { await refresh() }
    }

    /// Применить набор фильтров из общего окна. Перезагрузку инициирует вызывающий:
    /// экран знает, когда окно закрылось, а модель — нет.
    func setFilters(category: String, when: String?, freeOnly: Bool) {
        self.category = category
        self.when = when
        self.freeOnly = freeOnly
    }

    /// Холодный старт: расширить радиус до подсказанного и перезагрузить.
    func expandRadius() {
        guard let suggested = suggestedRadiusKm else { return }
        radiusKm = suggested
        Task { await refresh() }
    }

    func refresh() async {
        nextCursor = nil
        await load(reset: true)
    }

    func loadMoreIfNeeded(current item: EventListItem) async {
        guard item.id == items.last?.id, nextCursor != nil else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard let api, !isLoading else { return }
        isLoading = true; errorText = nil
        defer { isLoading = false }
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        do {
            // Без координат сервер отдаёт всё подряд — это и есть «все города».
            let everywhere = scope == .everywhere
            let resp: EventListResponse = try await api.send(Endpoint(
                path: "/events",
                query: [
                    "lat": everywhere ? nil : String(latitude),
                    "lng": everywhere ? nil : String(longitude),
                    "radius_km": everywhere ? nil : String(radiusKm),
                    "when": when,
                    "category": category.isEmpty ? nil : category,
                    "free_only": freeOnly ? "true" : nil,
                    "query": trimmedQuery.isEmpty ? nil : trimmedQuery,
                    "limit": "20",
                    "cursor": reset ? nil : nextCursor,
                ]
            ))
            items = reset ? resp.items : items + resp.items
            nextCursor = resp.nextCursor
            if reset {
                suggestedRadiusKm = resp.suggestedRadiusKm
                suggestedCount = resp.suggestedCount
            }
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось загрузить ленту"
        }
    }
}
