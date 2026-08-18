import Foundation

struct LastMessage: Decodable, Hashable {
    let text: String
    let createdAt: String
    let senderName: String?
    private enum CodingKeys: String, CodingKey {
        case text
        case createdAt = "created_at"
        case senderName = "sender_name"
    }
}

struct ConversationListItem: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String?
    let avatarURL: String?
    let eventID: String?
    let membersCount: Int
    let lastMessage: LastMessage?
    let unreadCount: Int
    let isArchived: Bool

    private enum CodingKeys: String, CodingKey {
        case id, type, title
        case avatarURL = "avatar_url"
        case eventID = "event_id"
        case membersCount = "members_count"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case isArchived = "is_archived"
    }
}

struct ConversationListResponse: Decodable {
    let items: [ConversationListItem]
    let nextCursor: String?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// Полная карточка беседы (GET /conversations/{id}) — для групп V2.
struct ConversationDetail: Decodable, Identifiable {
    let id: String
    let type: String
    let title: String?
    let avatarURL: String?
    let eventID: String?
    let membersCount: Int
    let unreadCount: Int
    let isArchived: Bool
    let members: [UserPublic]
    let myRole: String            // owner | member

    var isOwner: Bool { myRole == "owner" }

    private enum CodingKeys: String, CodingKey {
        case id, type, title, members
        case avatarURL = "avatar_url"
        case eventID = "event_id"
        case membersCount = "members_count"
        case unreadCount = "unread_count"
        case isArchived = "is_archived"
        case myRole = "my_role"
    }
}

// Тела запросов групп (V2).
struct CreateGroupBody: Encodable {
    let title: String
    let member_ids: [String]
    let from_event_id: String?
}
struct AddMembersBody: Encodable { let user_ids: [String] }
struct UpdateConversationBody: Encodable { let title: String }

struct Message: Decodable, Identifiable, Hashable {
    let id: String
    let conversationID: String
    let sender: UserPublic?
    let text: String
    let isSystem: Bool
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, sender, text
        case conversationID = "conversation_id"
        case isSystem = "is_system"
        case createdAt = "created_at"
    }
}

struct MessagesResponse: Decodable {
    let items: [Message]
    let nextCursor: String?
    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}
