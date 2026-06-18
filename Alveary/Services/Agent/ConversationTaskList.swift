import Foundation

struct ConversationTaskListSnapshot: Codable, Equatable, Sendable {
    let id: String
    let items: [ConversationTaskListItem]

    init(id: String, items: [ConversationTaskListItem]) {
        self.id = id
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        items = try container.decodeIfPresent([ConversationTaskListItem].self, forKey: .items) ?? []
    }
}

struct ConversationTaskListItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let content: String
    let activeForm: String?
    let status: ConversationTaskListStatus

    init(
        id: String,
        content: String,
        activeForm: String? = nil,
        status: ConversationTaskListStatus = .pending
    ) {
        self.id = id
        self.content = content
        self.activeForm = activeForm
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        activeForm = try container.decodeIfPresent(String.self, forKey: .activeForm)
        status = try container.decodeIfPresent(ConversationTaskListStatus.self, forKey: .status) ?? .pending
    }
}

enum ConversationTaskListStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.pending.rawValue:
            self = .pending
        case Self.inProgress.rawValue, "inProgress":
            self = .inProgress
        case Self.completed.rawValue:
            self = .completed
        default:
            self = .pending
        }
    }
}
