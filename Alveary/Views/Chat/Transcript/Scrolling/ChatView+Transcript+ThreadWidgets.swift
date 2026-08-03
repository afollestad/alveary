import Foundation

extension ChatTranscriptView {
    /// Wires the thread-management widgets' one action: selecting the thread the card names.
    /// The transcript cannot change the sidebar selection itself, so the ask goes to the app root.
    func configureAppKitThreadWidgets(_ configuration: inout AppKitTranscriptRowFactory.Configuration) {
        configuration.onOpenThread = { conversationID in
            NotificationCenter.default.post(
                name: .threadOpenRequested,
                object: nil,
                userInfo: [
                    ThreadOpenRequestNotificationKey.request: ThreadOpenRequest(conversationID: conversationID)
                ]
            )
        }
    }
}
