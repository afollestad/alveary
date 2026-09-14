import AgentCLIKit
import Foundation
import SwiftData

struct ToolApprovalTranscriptLookup: Sendable {
    let toolUseID: String
    let sessionID: String
    let workingDirectory: String
}

typealias ToolApprovalTranscriptReader = @Sendable (ToolApprovalTranscriptLookup) async -> ToolApprovalStatus?

/// Provider transcript reads can load and decode an entire JSONL file; never inherit the mounting view's main actor.
nonisolated func readClaudeToolApprovalTranscript(_ lookup: ToolApprovalTranscriptLookup) async -> ToolApprovalStatus? {
    await Task.detached(priority: .utility) {
        let resolution = ClaudeHookTranscriptReader().resolution(
            forToolUseId: AgentInteractionID(rawValue: lookup.toolUseID),
            sessionId: AgentSessionID(rawValue: lookup.sessionID),
            workingDirectoryPath: lookup.workingDirectory
        )
        switch resolution {
        case .some(.permissionDecision(.allow)): return .approved
        case .some(.permissionDecision(.deny)): return .denied
        case .some(.nonBlockingError): return .superseded
        case .some(.permissionDecision(.deferDecision)), .none: return nil
        }
    }.value
}

extension ConversationViewModel {
    func ensureToolApprovalRestorationFinished() throws {
        guard !state.isRestoringToolApproval else {
            throw AgentError.spawnFailed("Wait for the saved tool approval to finish loading")
        }
    }

    func restoreToolApproval(_ approval: ToolApprovalRequest) {
        guard (conversation.provider ?? settingsService.current.defaultProvider) == "claude" else {
            state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
            return
        }
        let token = UUID()
        let providerSessionID = conversation.providerSessionId ?? approval.sessionId
        toolApprovalRestoreToken = token
        state.isRestoringToolApproval = true
        toolApprovalRestoreTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishToolApprovalRestoration(token: token, providerSessionID: providerSessionID) }
            do {
                let status = try await self.resolvedToolApprovalStatusFromClaudeSession(approval)
                guard self.toolApprovalRestoreToken == token, self.state.pendingToolApproval == nil else { return }
                if let status {
                    self.persistToolApprovalStatus(status, toolUseId: approval.toolUseId, sessionId: approval.sessionId)
                } else {
                    self.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
                }
            } catch {
                // Cancellation or a changed conversation invalidates this snapshot; never install its old decision.
            }
        }
    }

    /// Also fences action-time reads, which are owned by their caller's outbound reservation rather than this task.
    func cancelToolApprovalRestoration() {
        toolApprovalTranscriptGeneration &+= 1
        toolApprovalRestoreTask?.cancel()
        toolApprovalRestoreTask = nil
        toolApprovalRestoreToken = nil
        state.isRestoringToolApproval = false
    }

    func resolvedToolApprovalStatusFromClaudeSession(_ approval: ToolApprovalRequest) async throws -> ToolApprovalStatus? {
        try Task.checkCancellation()
        guard let dbConversation = dbConversation(),
              (dbConversation.provider ?? settingsService.current.defaultProvider) == "claude",
              let workingDirectory = dbConversation.thread?.primaryWorkingDirectory else {
            return nil
        }
        let previousState = state
        let persistedApproval = unresolvedToolApproval(toolUseId: approval.toolUseId, sessionId: approval.sessionId)
        let providerSessionID = dbConversation.providerSessionId ?? approval.sessionId
        let generation = toolApprovalTranscriptGeneration
        let pendingApproval = state.pendingToolApproval
        let lookup = ToolApprovalTranscriptLookup(
            toolUseID: approval.toolUseId, sessionID: approval.sessionId, workingDirectory: workingDirectory
        )
        let status = await readToolApprovalTranscript(lookup)
        try Task.checkCancellation()
        guard state === previousState,
              toolApprovalTranscriptGeneration == generation,
              state.pendingToolApproval == pendingApproval,
              let currentConversation = fetchToolApprovalConversation(),
              (currentConversation.providerSessionId ?? approval.sessionId) == providerSessionID,
              (currentConversation.provider ?? settingsService.current.defaultProvider) == "claude",
              currentConversation.thread?.primaryWorkingDirectory == workingDirectory,
              unresolvedToolApproval(toolUseId: approval.toolUseId, sessionId: approval.sessionId) == persistedApproval else {
            throw CancellationError()
        }
        return status
    }

    private func fetchToolApprovalConversation() -> Conversation? {
        let conversationID = self.conversationID
        return try? modelContext.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationID })).first
    }

    private func finishToolApprovalRestoration(token: UUID, providerSessionID: String) {
        guard toolApprovalRestoreToken == token else { return }
        toolApprovalRestoreTask = nil
        toolApprovalRestoreToken = nil
        state.isRestoringToolApproval = false
        guard let conversation = fetchToolApprovalConversation(),
              (conversation.providerSessionId ?? providerSessionID) == providerSessionID,
              (conversation.provider ?? settingsService.current.defaultProvider) == "claude" else { return }
        // A live result can settle this row while its file read is pending. Discover the next
        // unresolved interaction synchronously, before allowing the parked queue to continue.
        hydratePendingToolApprovalIfNeeded()
        scheduleQueueDrainIfNeeded()
    }
}
