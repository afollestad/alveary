import Foundation

extension Notification.Name {
    static let scheduledTaskProposalsChanged = Notification.Name("scheduledTaskProposalsChanged")
}

enum ScheduledTaskProposalChangeUserInfoKey {
    static let proposalID = "proposalID"
    static let sourceConversationID = "sourceConversationID"
}

extension NotificationCenter {
    func postScheduledTaskProposalsChanged(
        object: Any? = nil,
        proposalID: String? = nil,
        sourceConversationID: String? = nil
    ) {
        var userInfo: [AnyHashable: Any] = [:]
        if let proposalID {
            userInfo[ScheduledTaskProposalChangeUserInfoKey.proposalID] = proposalID
        }
        if let sourceConversationID {
            userInfo[ScheduledTaskProposalChangeUserInfoKey.sourceConversationID] = sourceConversationID
        }
        post(
            name: .scheduledTaskProposalsChanged,
            object: object,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}
