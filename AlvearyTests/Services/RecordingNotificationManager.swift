import Foundation

@testable import Alveary

struct RecordedNotificationEvent {
    let event: ConversationEvent
    let conversationId: String
}

@MainActor
final class RecordingNotificationManager: NotificationManager {
    var handleEventCalls: [RecordedNotificationEvent] = []
    var markReadCalls: [String] = []
    var refreshBadgeCountCalls = 0
    var activeConversationProviderCalls = 0
    var handleAppVisibilityChangedCalls = 0

    func handleEvent(_ event: ConversationEvent, conversationId: String) {
        handleEventCalls.append(
            RecordedNotificationEvent(
                event: event,
                conversationId: conversationId
            )
        )
    }

    func markConversationRead(conversationId: String) {
        markReadCalls.append(conversationId)
    }

    func handleAppVisibilityChanged() {
        handleAppVisibilityChangedCalls += 1
    }

    func refreshBadgeCount() {
        refreshBadgeCountCalls += 1
    }

    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?) {
        activeConversationProviderCalls += 1
    }
}
