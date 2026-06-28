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
                viewModel.resumeQueuedMessages()
            },
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

    var queuedMessagesPauseHeaderTitle: String? {
        switch viewModel.state.queuedMessagesPauseReason {
        case .some(.interrupted):
            "Queue paused because you interrupted"
        case nil:
            nil
        }
    }
}
