import BlockInputKit
import Foundation

extension ChatView {
    var composerQueuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration? {
        guard !viewModel.messageQueue.pending.isEmpty else {
            return nil
        }
        return AppKitChatQueuedMessagesConfiguration(
            queuedMessages: viewModel.messageQueue.pending,
            supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
            isTurnActive: viewModel.canSteerCurrentTurn,
            inFlightQueuedMessageID: viewModel.state.inFlightQueuedMessageID,
            isInteractionDisabled: voiceInputCoordinator.isDraftInteractionLocked,
            borderWidth: 1,
            pauseHeaderTitle: queuedMessagesPauseHeaderTitle,
            markdownBaseURL: workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) },
            onOpenMarkdownLink: { url in
                _ = openComposerEditorURL(url)
            },
            onOpenMarkdownImage: { image, baseURL in
                appState.presentImagePreview(.markdownImage(image, baseURL: baseURL))
            },
            onResume: {
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                viewModel.resumeQueuedMessages()
            },
            onSteer: { messageID in
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                Task { try? await viewModel.steerQueuedMessage(id: messageID) }
            },
            onEdit: { messageID in
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                viewModel.editQueuedMessage(id: messageID)
            },
            onDismiss: { messageID in
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                viewModel.removeQueuedMessage(id: messageID)
            }
        )
    }

    var queuedMessagesPauseHeaderTitle: String? {
        switch viewModel.state.queuedMessagesPauseReason {
        case .some(.interrupted):
            "Queue paused because you interrupted"
        case nil:
            nil
        }
    }
}
