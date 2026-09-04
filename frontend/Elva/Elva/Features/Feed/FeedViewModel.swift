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

    /// Города, между которыми можно переключаться вручную и по которым
    /// определяется, куда человек попал по геопозиции.
    static let all: [City] = [
        City(name: "Москва", latitude: 55.7558, longitude: 37.6173),
        City(name: "Санкт-Петербург", latitude: 59.9343, longitude: 30.3351),
        City(name: "Новосибирск", latitude: 55.0084, longitude: 82.9357),
        City(name: "Екатеринбург", latitude: 56.8389, longitude: 60.6057),
        City(name: "Казань", latitude: 55.7963, longitude: 49.1088),
        City(name: "Нижний Новгород", latitude: 56.2965, longitude: 43.9361),
        City(name: "Челябинск", latitude: 55.1644, longitude: 61.4368),
        City(name: "Самара", latitude: 53.1959, longitude: 50.1002),
        City(name: "Омск", latitude: 54.9885, longitude: 73.3242),
        City(name: "Ростов-на-Дону", latitude: 47.2357, longitude: 39.7015),
        City(name: "Уфа", latitude: 54.7388, longitude: 55.9721),
        City(name: "Красноярск", latitude: 56.0153, longitude: 92.8932),
        City(name: "Воронеж", latitude: 51.6608, longitude: 39.2003),
        City(name: "Пермь", latitude: 58.0105, longitude: 56.2502),
        City(name: "Волгоград", latitude: 48.7080, longitude: 44.5133),
        City(name: "Краснодар", latitude: 45.0355, longitude: 38.9753),
        City(name: "Сочи", latitude: 43.6028, longitude: 39.7342),
        City(name: "Тюмень", latitude: 57.1522, longitude: 65.5272),
    ]

    /// Ближайший город списка, если человек внутри его агломерации.
    ///
    /// Радиус щедрый: пригород — это тот же город с точки зрения того, куда
    /// человек поедет вечером. Если ни один не подходит (например, человек за
    /// границей), возвращаем nil — лента останется на «всех городах».
    static func nearest(toLat lat: Double, lng: Double, withinKm limit: Double = 60) -> City? {
        var best: (city: City, km: Double)?
        for city in all {
            let km = distanceKm(lat, lng, city.latitude, city.longitude)
            if km <= limit, best == nil || km < best!.km { best = (city, km) }
        }
        return best?.city
    }

    private static func distanceKm(_ lat1: Double, _ lng1: Double,
                                   _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
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
        NotificationCenter.default.addObserver(
            forName: .userBlocked, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = UserBlocked.userID(from: note) else { return }
            Task { @MainActor [weak self] in self?.dropBlocked(organizerID: id) }
        }
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

    /// Контент заблокированного исчезает мгновенно; фоновое обновление следом
    /// приводит ленту к серверной правде.
    private func dropBlocked(organizerID: String) {
        items.removeAll { $0.organizer.id == organizerID }
        Task { await refresh() }
    }

    /// Координата от GPS. Игнорируется, если выбран конкретный город.
    ///
    /// В режиме «все города» точка всё равно нужна: от неё создаются события
    /// и желания, и по ней центрируется карта.
    func setCoordinate(lat: Double, lng: Double) {
        guard scope.city == nil else { return }
        latitude = lat
        longitude = lng
        adoptCityFromLocation()
    }

    /// Человек оказался в городе из списка — открываем сразу его город.
    ///
    /// Если ни один город не подходит (другая страна, посёлок вдали от
    /// перечисленных), остаёмся на «всех городах»: это лучше пустой ленты.
    /// Собственный выбор человека не трогаем — он всегда сильнее догадки.
    private func adoptCityFromLocation() {
        guard !hasExplicitChoice,
              let city = City.nearest(toLat: latitude, lng: longitude) else { return }
        scope = .city(city)
        latitude = city.latitude
        longitude = city.longitude
        Task { await refresh() }
    }

    /// Человек сам выбрал, что показывать. Тогда геопозиция ничего не меняет.
    private var hasExplicitChoice: Bool {
        UserDefaults.standard.string(forKey: scopeKey) != nil
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
