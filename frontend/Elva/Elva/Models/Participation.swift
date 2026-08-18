import Foundation

/// Статус участия. Строку с бэка приводим к типу через `init(raw:)` с безопасным
/// `.unknown` — новый статус на сервере не роняет декодирование и обрабатывается явно.
enum ParticipationStatus: String {
    /// `invited` — организатор позвал знакомого; место человек занимает сам, нажав «Иду».
    case invited, pending, accepted, waitlisted, rejected, cancelled
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

/// Строка экрана «Мои заявки»: статус отклика вместе с самим событием.
struct MyApplication: Decodable, Identifiable {
    let participationID: String
    let status: String
    let createdAt: String
    let event: EventListItem
    var id: String { participationID }

    private enum CodingKeys: String, CodingKey {
        case participationID = "participation_id"
        case status, event
        case createdAt = "created_at"
    }
}

struct MyApplicationsResponse: Decodable {
    let items: [MyApplication]
}

extension ParticipationStatus {
    /// Подпись и цвет для плашки статуса — одинаково во всех списках.
    var label: String {
        switch self {
        case .invited: "Вас позвали"
        case .pending: "Ждёт ответа"
        case .accepted: "Вы идёте"
        case .waitlisted: "В очереди"
        case .rejected: "Отказ"
        case .cancelled: "Отменён"
        case .unknown: "—"
        }
    }
}
