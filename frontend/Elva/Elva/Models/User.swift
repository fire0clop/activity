import Foundation

/// Публичный профиль (backend §9.3). Даты/таймстемпы держим строками — парсим при отображении.
struct UserPublic: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let bio: String?
    let avatarURL: String?
    let photoURLs: [String]
    let gender: String
    let age: Int?
    /// null, пока нет ни одного отзыва: у новичка рейтинга нет, а не «ноль».
    let ratingAvg: Double?
    let ratingCount: Int
    let eventsCreated: Int
    let eventsAttended: Int
    let noShowCount: Int?
    let memberSince: String

    /// Сколько раз человек не пришёл. Поле молодое — старый ответ сервера читаем как 0.
    var noShows: Int { noShowCount ?? 0 }
    /// Профиль без единой встречи и отзыва: организатору стоит прочитать «о себе».
    var isNewcomer: Bool { ratingCount == 0 && eventsAttended == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, bio, gender, age
        case avatarURL = "avatar_url"
        case photoURLs = "photo_urls"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case eventsCreated = "events_created"
        case eventsAttended = "events_attended"
        case noShowCount = "no_show_count"
        case memberSince = "member_since"
    }
}

/// Приватный профиль (/users/me).
struct UserPrivate: Decodable {
    let id: String
    let name: String?
    let bio: String?
    let avatarURL: String?
    let photoURLs: [String]
    let gender: String
    let age: Int?
    let ratingAvg: Double?
    let ratingCount: Int
    let eventsCreated: Int
    let eventsAttended: Int
    let noShowCount: Int?
    let memberSince: String
    let phone: String?   // null у аккаунтов, созданных через Apple
    let isPhoneVerified: Bool
    let birthDate: String?
    let profileCompleted: Bool
    let tosAcceptedVersion: String?

    var noShows: Int { noShowCount ?? 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, bio, gender, age, phone
        case avatarURL = "avatar_url"
        case photoURLs = "photo_urls"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case eventsCreated = "events_created"
        case eventsAttended = "events_attended"
        case noShowCount = "no_show_count"
        case memberSince = "member_since"
        case isPhoneVerified = "is_phone_verified"
        case birthDate = "birth_date"
        case profileCompleted = "profile_completed"
        case tosAcceptedVersion = "tos_accepted_version"
    }
}

/// Тело PATCH /users/me — все поля опциональны.
struct UpdateProfileBody: Encodable {
    var name: String?
    var bio: String?
    var birth_date: String?
    var gender: String?
}

struct AvatarResponse: Decodable {
    let avatarURL: String
    private enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" }
}

struct PhotosResponse: Decodable {
    let photoURLs: [String]
    private enum CodingKeys: String, CodingKey { case photoURLs = "photo_urls" }
}

/// Знакомый — человек, с которым была общая завершённая встреча.
///
/// Каталога людей в приложении нет: этот список нельзя пополнить поиском,
/// он растёт только от реальных встреч.
struct Connection: Decodable, Identifiable {
    let user: UserPublic
    let meetings: Int
    let lastMetAt: String
    let lastEventTitle: String
    let iFollow: Bool
    let followsMe: Bool
    let mutual: Bool
    var id: String { user.id }

    private enum CodingKeys: String, CodingKey {
        case user, meetings, mutual
        case lastMetAt = "last_met_at"
        case lastEventTitle = "last_event_title"
        case iFollow = "i_follow"
        case followsMe = "follows_me"
    }
}

struct ConnectionsResponse: Decodable {
    let items: [Connection]
}

struct DirectChatResponse: Decodable {
    let conversationID: String
    private enum CodingKeys: String, CodingKey { case conversationID = "conversation_id" }
}

/// Отношение зрителя к чужому профилю: подписка и факт совместной встречи.
struct FollowStatusResponse: Decodable {
    let following: Bool
    let met: Bool?
    /// Старый ответ сервера без поля — считаем, что не виделись.
    var haveMet: Bool { met ?? false }
}

struct InviteBody: Encodable {
    let user_ids: [String]
}

struct InviteResponse: Decodable {
    let invited: Int
    let skipped: Int
}
