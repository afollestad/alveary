import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: String
    var title: String?
    var provider: String?
    var isActive: Bool
    var isMain: Bool
    var displayOrder: Int
    var thread: AgentThread?
    @Relationship(deleteRule: .cascade, inverse: \ConversationEventRecord.conversation) var events: [ConversationEventRecord]

    init(
        id: String = UUID().uuidString,
        title: String? = nil,
        provider: String? = nil,
        isActive: Bool = true,
        isMain: Bool = true,
        displayOrder: Int = 0,
        thread: AgentThread? = nil,
        events: [ConversationEventRecord] = []
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.isActive = isActive
        self.isMain = isMain
        self.displayOrder = displayOrder
        self.thread = thread
        self.events = events
    }
}
