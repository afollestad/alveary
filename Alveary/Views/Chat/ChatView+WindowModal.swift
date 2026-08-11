import SwiftUI

extension ChatView {
    /// The chat window's single modal slot. Voice-model preparation outranks the paused-queue
    /// confirmation because it blocks the window until preparation finishes.
    var chatWindowModal: AppWindowModalOverlayPresenter.Modal? {
        voiceInputModelModal ?? pausedQueueSendModal
    }

    func dismissChatWindowModal() {
        guard voiceInputModelModal == nil else {
            return
        }
        dismissPausedQueueSendConfirmation()
    }
}
