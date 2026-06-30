import Foundation

struct JoinResponse: Decodable {
    let status: String
}

struct ParticipantItem: Decodable, Identifiable {
    let participationID: String
    let user: UserPublic
    let status: String
    let createdAt: String
    var id: String { participationID }

    private enum CodingKeys: String, CodingKey {
        case participationID = "participation_id"
        case user, status
        case createdAt = "created_at"
    }
}

struct ParticipantsResponse: Decodable {
    let items: [ParticipantItem]
}
