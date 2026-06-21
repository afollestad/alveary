import SwiftData
import SwiftUI

extension ContentView {
    func activeDiffActionTarget() -> (thread: AgentThread, conversation: Conversation)? {
        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              let thread = uiModelContext.resolveThread(id: selectedThread.persistentModelID),
              let conversation = selectedConversation(in: thread, modelContext: uiModelContext, appState: appState) else {
            return nil
        }

        return (thread, conversation)
    }

    func presentGitCommitModal() {
        guard let (thread, _) = activeDiffActionTarget(),
              let directory = diffViewModel.activeDirectory else {
            return
        }

        let baseBranch = thread.project?.baseRef ?? "main"
        let context = DiffGitCommitModalContext(
            directory: directory,
            threadName: thread.displayName(),
            baseBranch: baseBranch,
            remoteName: thread.project?.remoteName
        )

        gitCommitModalModel = DiffGitCommitModalModel(
            context: context,
            gitService: gitService,
            settingsService: settingsService,
            generateCommitMessage: { prompt in
                try await generateCommitMessage(prompt: prompt)
            },
            refreshAfterMutation: {
                await diffViewModel.refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
            }
        )
    }

    func requestCommitMessageGeneration(
        prompt: String,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        guard let (_, conversation) = activeDiffActionTarget() else {
            completion(.failure(CommitMessageGenerationError.activeConversationChanged))
            return
        }

        appState.requestCommitMessageGeneration(
            prompt: prompt,
            conversationID: conversation.persistentModelID,
            completion: completion
        )
    }

    func generateCommitMessage(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            requestCommitMessageGeneration(prompt: prompt) { result in
                continuation.resume(with: result)
            }
        }
    }

    func requestAgentOpenPR() {
        guard let (thread, conversation) = activeDiffActionTarget() else {
            return
        }

        let baseRef = thread.project?.baseRef ?? "main"
        let message = "Please push or publish the current branch if needed, then open a pull request against `\(baseRef)` and share the PR URL."
        appState.requestDiffAction(message: message, conversationID: conversation.persistentModelID)
    }

    func cancelPendingDiffActionIfNeeded() {
        guard let request = appState.pendingDiffAction else {
            return
        }

        guard let activeConversationID = activeDiffActionTarget()?.conversation.persistentModelID,
              activeConversationID == request.conversationID else {
            appState.pendingDiffAction = nil
            return
        }
    }

    func cancelPendingCommitMessageGenerationIfNeeded() {
        guard let request = appState.pendingCommitMessageGenerationRequest else {
            return
        }

        guard let activeConversationID = activeDiffActionTarget()?.conversation.persistentModelID,
              activeConversationID == request.conversationID else {
            appState.cancelPendingCommitMessageGenerationRequest()
            return
        }
    }
}
