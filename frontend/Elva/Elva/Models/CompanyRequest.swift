import Foundation

/// «Ищу компанию» — намерение без обязательств.
///
/// Обратная сторона события: не «организую теннис в 19:00», а «хочу на теннис
/// где-то на неделе». Точного времени и адреса здесь нет — они появляются, когда
/// кто-то берёт запрос на себя и заводит из него настоящее событие.
struct CompanyRequest: Decodable, Identifiable, Hashable {
    let id: String
    let author: OrganizerBrief
    let category: String
    let text: String?
    let area: String?
    let radiusKm: Double
    let whenWindow: String
    let status: String
    let supportsCount: Int
    let iSupport: Bool
    let isMine: Bool
    let distanceKm: Double?
    let latitude: Double
    let longitude: Double
    let fulfilledEventID: String?
    let createdAt: String
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case id, author, category, text, area, status, latitude, longitude
        case radiusKm = "radius_km"
        case whenWindow = "when_window"
        case supportsCount = "supports_count"
        case iSupport = "i_support"
        case isMine = "is_mine"
        case distanceKm = "distance_km"
        case fulfilledEventID = "fulfilled_event_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct CompanyRequestsResponse: Decodable {
    let items: [CompanyRequest]
    let nextCursor: String?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct CompanyRequestCreateBody: Encodable {
    let category: String
    let text: String?
    let latitude: Double
    let longitude: Double
    let area: String?
    let radius_km: Double
    let when_window: String
}

struct SupportResponse: Decodable {
    let supportsCount: Int
    let iSupport: Bool
    private enum CodingKeys: String, CodingKey {
        case supportsCount = "supports_count"
        case iSupport = "i_support"
    }
}

/// Окно «когда» — вместо точного времени, которого у желания ещё нет.
enum WhenWindow: String, CaseIterable, Identifiable {
    case today, tomorrow, weekend, week
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Сегодня"
        case .tomorrow: "Завтра"
        case .weekend: "В выходные"
        case .week: "На неделе"
        }
    }
}

/// Ответ на «меня открыли по ссылке на событие?» после установки приложения.
struct PendingDeeplinkResponse: Decodable {
    let eventID: String?
    private enum CodingKeys: String, CodingKey { case eventID = "event_id" }
}
