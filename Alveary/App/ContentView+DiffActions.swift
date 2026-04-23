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

    func requestAgentCommit() {
        guard let (_, conversation) = activeDiffActionTarget() else {
            return
        }

        let message: String
        if diffViewModel.files.contains(where: { $0.isStaged }) {
            message = "Please review the currently staged changes in this worktree and create an appropriate git commit for them."
        } else {
            message = "Please review the current uncommitted changes in this worktree and create an appropriate git commit."
        }

        appState.requestDiffAction(message: message, conversationID: conversation.persistentModelID)
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
}
