import Foundation

struct Review: Decodable, Identifiable {
    let id: String
    let eventID: String
    let author: UserPublic
    let targetID: String
    /// Пусто у отметки о неявке — оценивать было нечего.
    let rating: Int?
    let comment: String?
    let attended: Bool?
    let createdAt: String

    /// Старый ответ сервера без поля читаем как «пришёл».
    var didAttend: Bool { attended ?? true }

    private enum CodingKeys: String, CodingKey {
        case id, author, rating, comment, attended
        case eventID = "event_id"
        case targetID = "target_id"
        case createdAt = "created_at"
    }
}

struct ReviewsResponse: Decodable {
    let items: [Review]
    let nextCursor: String?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct ReviewCreateBody: Encodable {
    let target_id: String
    /// nil вместе с attended=false: неявку оценкой не выражают.
    let rating: Int?
    let comment: String?
    var attended: Bool = true
}
