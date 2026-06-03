import Foundation

extension ChatView {
    var composerQueuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration? {
        guard !viewModel.messageQueue.pending.isEmpty else {
            return nil
        }
        return AppKitChatQueuedMessagesConfiguration(
            queuedMessages: viewModel.messageQueue.pending,
            supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
            isTurnActive: viewModel.state.turnState.isActive || runtimeStatus == .busy,
            inFlightQueuedMessageID: viewModel.state.inFlightQueuedMessageID,
            borderWidth: 1,
            onSteer: { messageID in
                Task { try? await viewModel.steerQueuedMessage(id: messageID) }
            },
            onEdit: { messageID in
                viewModel.editQueuedMessage(id: messageID)
            },
            onDismiss: { messageID in
                viewModel.removeQueuedMessage(id: messageID)
            }
        )
    }
}
