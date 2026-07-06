import Foundation

/// Статус участия. Строку с бэка приводим к типу через `init(raw:)` с безопасным
/// `.unknown` — новый статус на сервере не роняет декодирование и обрабатывается явно.
enum ParticipationStatus: String {
    case pending, accepted, waitlisted, rejected, cancelled
    case unknown

    init(raw: String?) {
        self = raw.flatMap { ParticipationStatus(rawValue: $0) } ?? .unknown
    }
}

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
