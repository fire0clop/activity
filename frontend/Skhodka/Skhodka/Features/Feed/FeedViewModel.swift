import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var items: [EventListItem] = []
    @Published var isLoading = false
    @Published var errorText: String?

    // Фильтры
    @Published var when: String?        // nil | today | tomorrow | weekend
    @Published var query: String = ""
    @Published var radiusKm: Double = 30

    // Координаты (по умолчанию центр Москвы, пока нет геолокации)
    private(set) var latitude = 55.751
    private(set) var longitude = 37.618

    private var nextCursor: String?
    private var api: APIClient?

    func configure(_ api: APIClient) { self.api = api }

    func setCoordinate(lat: Double, lng: Double) {
        latitude = lat
        longitude = lng
    }

    func setWhen(_ value: String?) {
        when = (when == value) ? nil : value
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
        } catch let err as APIError {
            errorText = err.message
        } catch {
            errorText = "Не удалось загрузить ленту"
        }
    }
}
