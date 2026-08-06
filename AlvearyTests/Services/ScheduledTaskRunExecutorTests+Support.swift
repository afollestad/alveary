import Foundation

@testable import Alveary

@MainActor
final class ScheduledExecutionNotificationRecorder: NotificationManager {
    private(set) var refreshBadgeCountCalls = 0
    private(set) var handledEvents: [(event: ConversationEvent, conversationID: String)] = []
    var onHandleEvent: (@MainActor (ConversationEvent, String) -> Void)?

    func handleEvent(_ event: ConversationEvent, conversationId: String) {
        handledEvents.append((event, conversationId))
        onHandleEvent?(event, conversationId)
    }
    func markConversationRead(conversationId: String) {}
    func handleAppVisibilityChanged() {}
    func requestAuthorizationIfNeeded() async {}
    func refreshBadgeCount() { refreshBadgeCountCalls += 1 }
    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?) {}
}
