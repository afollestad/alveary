import SwiftData

extension ConversationView {
    func handlePendingCommitMessageGenerationRequest() async {
        guard let request = appState.pendingCommitMessageGenerationRequest,
              request.conversationID == conversation.persistentModelID else {
            return
        }

        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              selectedThread.persistentModelID == request.threadID,
              request.threadID == conversation.thread?.persistentModelID else {
            appState.completeCommitMessageGenerationRequest(
                id: request.id,
                result: .failure(CommitMessageGenerationError.activeConversationChanged)
            )
            return
        }

        do {
            let message = try await viewModel.generateCommitMessage(request.prompt)
            // Every outcome routes through the ID-checked completion, so a stale
            // conversation task resolves nothing instead of resuming twice.
            appState.completeCommitMessageGenerationRequest(id: request.id, result: .success(message))
        } catch {
            appState.completeCommitMessageGenerationRequest(id: request.id, result: .failure(error))
        }
    }
}
