import Foundation

@testable import Alveary

struct PostedNotification: Equatable {
    let context: ConversationNotificationContext
    let message: String
    let playSound: Bool
}

@MainActor
final class NotificationSpy {
    var playedSounds: [String] = []
    var postedNotifications: [PostedNotification] = []
    var dismissedConversationIds: [String] = []
    var badgeCounts: [Int] = []
}
