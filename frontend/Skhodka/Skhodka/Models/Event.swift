import Foundation

struct OrganizerBrief: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let avatarURL: String?
    /// null, пока об организаторе никто не написал отзыв.
    let ratingAvg: Double?
    let ratingCount: Int?

    /// Число отзывов; поле молодое — старый ответ сервера читаем как 0.
    var reviewsCount: Int { ratingCount ?? 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
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
    // Холодный старт: если в радиусе пусто — ближайший радиус с событиями.
    let suggestedRadiusKm: Double?
    let suggestedCount: Int?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case suggestedRadiusKm = "suggested_radius_km"
        case suggestedCount = "suggested_count"
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
/// Как участники платят. Три случая покрывают почти всё, что бывает офлайн.
enum PriceSplit: String, CaseIterable, Identifiable {
    /// Ничего платить не нужно.
    case free
    /// Каждый платит за себя, общей суммы нет: гидроциклы, билеты, свой обед.
    case perPerson = "per_person"
    /// Есть общий счёт, который делится на пришедших: выкуп зала, аренда дома, катер.
    case shared

    var id: String { rawValue }

    init(raw: String?) {
        self = raw.flatMap { PriceSplit(rawValue: $0) } ?? .free
    }

    var title: String {
        switch self {
        case .free: "Бесплатно"
        case .perPerson: "С каждого"
        case .shared: "Общий счёт"
        }
    }

    var hint: String {
        switch self {
        case .free: "Участие ничего не стоит."
        case .perPerson: "Каждый платит сам за себя — общей суммы, которую нужно собрать, нет."
        case .shared: "Одна сумма на всех: она делится на тех, кто придёт. Чем больше людей, тем дешевле каждому."
        }
    }
}

/// Как показать цену в ленте и в карточке.
///
/// Главное здесь — общий счёт: сумма делится на реальное число участников, поэтому
/// «с человека» меняется по мере набора. Показываем обе цифры, чтобы на встрече не
/// выяснялось, кто сколько должен.
enum Pricing {
    static func amount(_ value: Double) -> String {
        let n = NSNumber(value: value.rounded())
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return (f.string(from: n) ?? "\(Int(value))") + " ₽"
    }

    /// Короткая подпись для карточки в ленте.
    static func short(price: Double?, split: String?, current: Int) -> String {
        let split = PriceSplit(raw: split)
        guard let price, price > 0, split != .free else { return "бесплатно" }
        switch split {
        case .free: return "бесплатно"
        case .perPerson: return amount(price)
        case .shared: return amount(perHead(price: price, current: current))
        }
    }

    /// Сколько выходит с человека прямо сейчас (для общего счёта).
    static func perHead(price: Double, current: Int) -> Double {
        price / Double(max(current, 1))
    }

    /// Крупное значение и подпись под ним для блока фактов.
    static func detail(price: Double?, split: String?, current: Int,
                       max maxCount: Int?) -> (value: String, caption: String) {
        let split = PriceSplit(raw: split)
        guard let price, price > 0, split != .free else {
            return ("Free", "бесплатно")
        }
        switch split {
        case .free:
            return ("Free", "бесплатно")
        case .perPerson:
            return (amount(price), "с человека")
        case .shared:
            let now = amount(perHead(price: price, current: current))
            if let maxCount, maxCount > current {
                let best = amount(perHead(price: price, current: maxCount))
                return (now, "с человека сейчас · \(best) при полном составе")
            }
            return (now, "с человека · \(amount(price)) на всех")
        }
    }
}

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
    /// Событие собрано по чужому «хочу»: сервер закроет запрос и позовёт тех, кто его ждал.
    var from_request_id: String? = nil
}
