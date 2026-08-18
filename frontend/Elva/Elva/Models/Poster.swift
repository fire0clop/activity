import Foundation

/// Афиша — чужое мероприятие, на которое можно сходить.
///
/// Отличается от события тем, что тут никто не собирает группу: концерт состоится
/// независимо от откликов, организатора среди пользователей нет, заявок и чата нет.
/// Связь с ядром одна: из карточки можно собрать компанию — тогда появится обычное
/// событие, ссылающееся сюда.
struct PosterItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let category: String?
    let startsAt: String
    let endsAt: String?
    let venue: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let distanceKm: Double?
    let priceFrom: Double?
    let isFree: Bool
    let imageURL: String?
    let sourceURL: String?
    let sourceName: String?
    /// Сколько компаний уже собирается сюда.
    let gatheringsCount: Int
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id, title, description, category, venue, address, latitude, longitude, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case distanceKm = "distance_km"
        case priceFrom = "price_from"
        case isFree = "is_free"
        case imageURL = "image_url"
        case sourceURL = "source_url"
        case sourceName = "source_name"
        case gatheringsCount = "gatherings_count"
    }
}

struct PosterResponse: Decodable {
    let items: [PosterItem]
    let nextCursor: String?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// Категория из справочника: канонические плюс те, что вписали пользователи.
struct CategoryItem: Decodable, Hashable {
    let key: String
    let title: String
    let isCanonical: Bool
    let usage: Int

    private enum CodingKeys: String, CodingKey {
        case key, title, usage
        case isCanonical = "is_canonical"
    }
}

struct CategoriesResponse: Decodable {
    let items: [CategoryItem]
}
