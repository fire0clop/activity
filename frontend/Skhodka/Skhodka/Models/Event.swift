import Foundation

struct OrganizerBrief: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let avatarURL: String?
    let ratingAvg: Double
    private enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
        case ratingAvg = "rating_avg"
    }
}

/// Карточка события в ленте (backend §9.4). Время скрыто, пока time_disclosed=false.
struct EventListItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let category: String?
    let day: String
    let startsAt: String?
    let endsAt: String?
    let timeDisclosed: Bool
    let latitude: Double
    let longitude: Double
    let address: String?
    let mapURL: String?
    let coverURL: String?
    let photoURLs: [String]
    let participantsCurrent: Int
    let participantsMax: Int?      // nil = без ограничения
    let price: Double?
    let priceSplit: String
    let status: String
    let distanceKm: Double?
    let organizer: OrganizerBrief

    /// Все картинки события для слайдера: обложка + галерея.
    var images: [String] {
        var result: [String] = []
        if let coverURL { result.append(coverURL) }
        result.append(contentsOf: photoURLs.filter { $0 != coverURL })
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, day, latitude, longitude, address, price, status, organizer
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeDisclosed = "time_disclosed"
        case mapURL = "map_url"
        case coverURL = "cover_url"
        case photoURLs = "photo_urls"
        case participantsCurrent = "participants_current"
        case participantsMax = "participants_max"
        case priceSplit = "price_split"
        case distanceKm = "distance_km"
    }
}

struct MyParticipation: Decodable, Hashable {
    let status: String
}

/// Полная карточка события (/events/{id}).
struct EventDetail: Decodable, Identifiable {
    let id: String
    let title: String
    let category: String?
    let day: String
    let startsAt: String?
    let endsAt: String?
    let timeDisclosed: Bool
    let latitude: Double
    let longitude: Double
    let address: String?
    let mapURL: String?
    let coverURL: String?
    let participantsCurrent: Int
    let participantsMax: Int?      // nil = без ограничения
    let price: Double?
    let priceSplit: String
    let status: String
    let distanceKm: Double?
    let organizer: OrganizerBrief
    let description: String?
    let minParticipants: Int
    let autoAccept: Bool
    let createdAt: String
    let photoURLs: [String]
    let acceptedParticipants: [OrganizerBrief]
    let myParticipation: MyParticipation?
    let isOrganizer: Bool
    let chatAvailable: Bool
    let conversationID: String?

    /// Обложка + галерея для слайдера.
    var images: [String] {
        var result: [String] = []
        if let coverURL { result.append(coverURL) }
        result.append(contentsOf: photoURLs.filter { $0 != coverURL })
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, day, latitude, longitude, address, price, status, organizer, description
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeDisclosed = "time_disclosed"
        case mapURL = "map_url"
        case coverURL = "cover_url"
        case participantsCurrent = "participants_current"
        case participantsMax = "participants_max"
        case priceSplit = "price_split"
        case distanceKm = "distance_km"
        case minParticipants = "min_participants"
        case autoAccept = "auto_accept"
        case createdAt = "created_at"
        case photoURLs = "photo_urls"
        case acceptedParticipants = "accepted_participants"
        case myParticipation = "my_participation"
        case isOrganizer = "is_organizer"
        case chatAvailable = "chat_available"
        case conversationID = "conversation_id"
    }
}

struct EventListResponse: Decodable {
    let items: [EventListItem]
    let nextCursor: String?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// Тело PATCH /events/{id} — все поля опциональны (шлём только изменённые).
struct UpdateEventBody: Encodable {
    var title: String?
    var description: String?
    var category: String?
    var starts_at: String?
    var map_url: String?
    var address: String?
    var max_participants: Int?
    var price: Double?
    var price_split: String?
    var auto_accept: Bool?
}


/// Тело POST /events. Координаты задаются ссылкой Яндекс.Карт (map_url) либо напрямую.
struct CreateEventBody: Encodable {
    let title: String
    let description: String?
    let category: String?
    let starts_at: String
    let ends_at: String?
    let map_url: String?
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let min_participants: Int
    let max_participants: Int?      // nil = без ограничения
    let price: Double?
    let price_split: String
    let auto_accept: Bool
    var recurrence: String = "none"   // none | weekly
}
