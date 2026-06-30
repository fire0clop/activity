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
    let ratingAvg: Double
    let ratingCount: Int
    let eventsCreated: Int
    let eventsAttended: Int
    let memberSince: String

    private enum CodingKeys: String, CodingKey {
        case id, name, bio, gender, age
        case avatarURL = "avatar_url"
        case photoURLs = "photo_urls"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case eventsCreated = "events_created"
        case eventsAttended = "events_attended"
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
    let ratingAvg: Double
    let ratingCount: Int
    let eventsCreated: Int
    let eventsAttended: Int
    let memberSince: String
    let phone: String
    let isPhoneVerified: Bool
    let birthDate: String?
    let profileCompleted: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, bio, gender, age, phone
        case avatarURL = "avatar_url"
        case photoURLs = "photo_urls"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case eventsCreated = "events_created"
        case eventsAttended = "events_attended"
        case memberSince = "member_since"
        case isPhoneVerified = "is_phone_verified"
        case birthDate = "birth_date"
        case profileCompleted = "profile_completed"
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
