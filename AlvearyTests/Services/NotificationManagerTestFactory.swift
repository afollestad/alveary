import Foundation
import SwiftData

@testable import Alveary

struct NotificationManagerTestContext {
    let container: ModelContainer
}

struct SeededNotificationConversations {
    let threadName: String
    let mainConversationId: String
    let extraConversationIds: [String]
}

@MainActor
enum NotificationManagerTestFactory {
    static func makeContext() throws -> NotificationManagerTestContext {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return NotificationManagerTestContext(container: container)
    }

    @discardableResult
    static func seedConversation(
        in container: ModelContainer,
        threadName: String,
        conversationTitle: String? = nil,
        isMain: Bool = true,
        isUnread: Bool = false,
        archivedAt: Date? = nil
    ) -> Conversation {
        let context = ModelContext(container)
        let thread = AgentThread(name: threadName, hasCustomName: true, archivedAt: archivedAt)
        let conversation = Conversation(
            title: conversationTitle,
            isMain: isMain,
            displayOrder: 0,
            isUnread: isUnread,
            thread: thread
        )
        context.insert(thread)
        context.insert(conversation)
        try? context.save()
        return conversation
    }

    static func seedThreadWithConversations(
        in container: ModelContainer,
        threadName: String,
        mainTitle: String?,
        extraTitles: [String]
    ) -> SeededNotificationConversations {
        let context = ModelContext(container)
        let thread = AgentThread(name: threadName, hasCustomName: true)
        context.insert(thread)
        let main = Conversation(title: mainTitle, isMain: true, displayOrder: 0, thread: thread)
        context.insert(main)
        var extras: [String] = []
        for (index, title) in extraTitles.enumerated() {
            let convo = Conversation(title: title, isMain: false, displayOrder: index + 1, thread: thread)
            context.insert(convo)
            extras.append(convo.id)
        }
        try? context.save()
        return SeededNotificationConversations(
            threadName: threadName,
            mainConversationId: main.id,
            extraConversationIds: extras
        )
    }

    static func fetchConversation(id: String, in container: ModelContainer) -> Conversation? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    static func makeManager(
        settingsService: InMemorySettingsService,
        modelContainer: ModelContainer,
        isAppInForeground: Bool,
        activeConversationId: String?,
        spy: NotificationSpy
    ) -> DefaultNotificationManager {
        let manager = DefaultNotificationManager(
            settingsService: settingsService,
            modelContainer: modelContainer,
            systemNotificationCenter: NotificationCenter()
        )
        manager.isAppInForeground = { isAppInForeground }
        manager.setActiveConversationProvider { activeConversationId }
        manager.playInAppSound = { spy.playedSounds.append($0) }
        manager.onPostNotification = { context, message, playSound in
            spy.postedNotifications.append(
                PostedNotification(
                    context: context,
                    message: message,
                    playSound: playSound
                )
            )
        }
        manager.onDismissDelivered = { conversationId in
            spy.dismissedConversationIds.append(conversationId)
        }
        manager.setBadgeCount = { count in
            spy.badgeCounts.append(count)
        }
        return manager
    }
}
