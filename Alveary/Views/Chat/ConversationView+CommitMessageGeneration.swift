import SwiftData

extension ConversationView {
    func handlePendingCommitMessageGenerationRequest() async {
        guard let request = appState.pendingCommitMessageGenerationRequest,
              request.conversationID == conversation.persistentModelID else {
            return
        }

        defer {
            appState.clearCommitMessageGenerationRequest(id: request.id)
        }

        guard appState.pendingCommitMessageGenerationRequest?.id == request.id,
              case .thread(let selectedThread) = appState.selectedSidebarItem,
              selectedThread.persistentModelID == conversation.thread?.persistentModelID,
              selectedConversation(
                  in: selectedThread,
                  modelContext: modelContext,
                  appState: appState
              )?.persistentModelID == conversation.persistentModelID else {
            request.completion(.failure(CommitMessageGenerationError.activeConversationChanged))
            return
        }

        do {
            let message = try await viewModel.generateCommitMessage(request.prompt)
            guard appState.pendingCommitMessageGenerationRequest?.id == request.id else {
                request.completion(.failure(CommitMessageGenerationError.activeConversationChanged))
                return
            }
            request.completion(.success(message))
        } catch {
            request.completion(.failure(error))
        }
    }
}
