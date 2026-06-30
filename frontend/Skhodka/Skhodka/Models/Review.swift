import Foundation

struct Review: Decodable, Identifiable {
    let id: String
    let eventID: String
    let author: UserPublic
    let targetID: String
    let rating: Int
    let comment: String?
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, author, rating, comment
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
    let rating: Int
    let comment: String?
}
