import Foundation

extension SidebarViewModel {
    func removeConversationAttachmentDirectories(_ conversationIDs: [String]) async {
        var seen = Set<String>()
        for conversationID in conversationIDs where seen.insert(conversationID).inserted {
            await attachmentStore.removeConversationDirectory(conversationId: conversationID)
        }
    }
}
