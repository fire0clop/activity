import Foundation

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
    @Published var when: String?        // nil | today | tomorrow | weekend
    @Published var query: String = ""
    @Published var radiusKm: Double = 30

    /// Город, выбранный вручную; nil — используем геолокацию.
    @Published private(set) var manualCity: City?

    // Координаты (по умолчанию центр Москвы, пока нет ни геолокации, ни города)
    private(set) var latitude = 55.751
    private(set) var longitude = 37.618

    private var nextCursor: String?
    private var api: APIClient?
    private let cityKey = "feed.manualCity"

    init() {
        if let data = UserDefaults.standard.data(forKey: cityKey),
           let city = try? JSONDecoder().decode(City.self, from: data) {
            manualCity = city
            latitude = city.latitude
            longitude = city.longitude
        }
    }

    func configure(_ api: APIClient) { self.api = api }

    /// Координата от GPS. Игнорируется, если пользователь выбрал город вручную.
    func setCoordinate(lat: Double, lng: Double) {
        guard manualCity == nil else { return }
        latitude = lat
        longitude = lng
    }

    /// Ручной выбор города; nil — вернуться к геолокации.
    func selectCity(_ city: City?) {
        manualCity = city
        if let city {
            latitude = city.latitude
            longitude = city.longitude
            if let data = try? JSONEncoder().encode(city) {
                UserDefaults.standard.set(data, forKey: cityKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: cityKey)
        }
        Task { await refresh() }
    }

    func setWhen(_ value: String?) {
        when = (when == value) ? nil : value
        Task { await refresh() }
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
            let resp: EventListResponse = try await api.send(Endpoint(
                path: "/events",
                query: [
                    "lat": String(latitude),
                    "lng": String(longitude),
                    "radius_km": String(radiusKm),
                    "when": when,
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
