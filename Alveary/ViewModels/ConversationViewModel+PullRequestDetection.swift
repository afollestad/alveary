import Foundation
import SwiftData

/// Detects GitHub pull-request links in transcript messages as they are persisted.
///
/// Detection only ever runs at insert time, so history copied onto a fork or
/// rebuilt from stored records never triggers, and `AgentThread.pullRequestScanWatermark`
/// fences replays of the same record. Linking itself belongs to
/// `PullRequestLinksViewModel`, so both the automatic and accepted paths post
/// `.pullRequestLinkRequested` rather than writing links here.
extension ConversationViewModel {
    func scanInsertedMessageRecordForPullRequestLinks(_ record: ConversationEventRecord) {
        guard record.type == ConversationEventRecord.messageType,
              record.role == ConversationEventRecord.userRole || record.role == ConversationEventRecord.assistantRole,
              // Sub-agent messages render inside their sub-agent block, so a prompt
              // row anchored to one would have no bubble to sit under.
              record.parentToolUseId == nil,
              let content = record.content,
              !content.isEmpty else {
            return
        }

        let settings = settingsService.current
        guard settings.pullRequestsEnabled else {
            return
        }
        let linksAutomatically = settings.automaticallyLinkPullRequests
        guard linksAutomatically || !settings.suppressPullRequestLinkPrompts else {
            return
        }

        guard let thread = dbThread(), !thread.isDraft else {
            return
        }
        if let watermark = thread.pullRequestScanWatermark, record.timestamp <= watermark {
            return
        }

        let identifiers = PullRequestURLTextScanner.identifiers(in: content)
        guard !identifiers.isEmpty else {
            return
        }
        thread.pullRequestScanWatermark = max(thread.pullRequestScanWatermark ?? .distantPast, record.timestamp)
        applyDetectedPullRequests(
            identifiers,
            from: record,
            to: thread,
            linksAutomatically: linksAutomatically
        )
        scheduleSave()
    }

    private func applyDetectedPullRequests(
        _ identifiers: [PullRequestIdentifier],
        from record: ConversationEventRecord,
        to thread: AgentThread,
        linksAutomatically: Bool
    ) {
        let threadID = thread.persistentModelID
        var prompts = thread.pendingPullRequestLinkPrompts
        var addedPrompt = false
        for identifier in identifiers where !thread.isPullRequestLinked(identifier) {
            // The automatic path deliberately ignores pending prompts: linking clears
            // any matching entry, so a question left over from before auto-linking was
            // turned on must not block the link forever.
            guard !linksAutomatically else {
                postPullRequestLinkRequest(identifier: identifier, threadID: threadID)
                continue
            }
            guard !prompts.contains(where: { $0.identifier == identifier }) else {
                continue
            }
            prompts.append(
                PendingPullRequestPrompt(
                    identifier: identifier,
                    messageEventID: record.id,
                    conversationID: record.conversationId,
                    createdAt: record.timestamp
                )
            )
            addedPrompt = true
        }
        if addedPrompt {
            thread.pendingPullRequestLinkPrompts = prompts
        }
    }

    /// Prompts for this conversation keyed by the message they anchor to. Answered,
    /// already-linked, and globally suppressed prompts are filtered out here rather
    /// than removed, so a stale entry cannot resurrect a question.
    func pendingPullRequestLinkPromptsByMessageID() -> [String: [PendingPullRequestPrompt]] {
        let settings = settingsService.current
        guard settings.pullRequestsEnabled,
              !settings.suppressPullRequestLinkPrompts,
              let thread = dbThread() else {
            return [:]
        }

        let conversationID = conversation.id
        let visible = thread.pendingPullRequestLinkPrompts
            .filter { $0.conversationID == conversationID && !thread.isPullRequestLinked($0.identifier) }
            .sorted { $0.createdAt < $1.createdAt }
        return Dictionary(grouping: visible, by: \.messageEventID)
    }

    /// `always` also turns automatic linking on; the entry is cleared when the link
    /// lands, so a failed link leaves the question answerable.
    func acceptPullRequestLinkPrompt(_ prompt: PendingPullRequestPrompt, always: Bool) {
        guard let thread = dbThread() else {
            return
        }
        if always {
            settingsService.update { $0.automaticallyLinkPullRequests = true }
        }
        postPullRequestLinkRequest(identifier: prompt.identifier, threadID: thread.persistentModelID)
    }

    /// `never` suppresses every future prompt without preventing automatic linking
    /// from being turned on later.
    func declinePullRequestLinkPrompt(_ prompt: PendingPullRequestPrompt, never: Bool) {
        if let thread = dbThread() {
            thread.pendingPullRequestLinkPrompts = thread.pendingPullRequestLinkPrompts.filter { $0.id != prompt.id }
            scheduleSave()
        }
        if never {
            settingsService.update { $0.suppressPullRequestLinkPrompts = true }
        }
    }

    /// Drops this conversation's prompts whose anchoring message no longer exists,
    /// so a deleted or retried message cannot strand an unanswerable question.
    ///
    /// It re-fetches rather than reusing the caller's records: rebuild callers may
    /// pass a stale query snapshot or an empty array from a failed fetch, and
    /// deleting every prompt because a fetch happened to throw would lose real
    /// questions. A throw here simply skips this pass.
    func prunePendingPullRequestPromptsWithMissingAnchors() {
        guard let thread = dbThread() else {
            return
        }
        let prompts = thread.pendingPullRequestLinkPrompts
        guard !prompts.isEmpty else {
            return
        }
        guard let liveRecordIDs = try? liveConversationRecordIDs() else {
            return
        }

        let conversationID = conversation.id
        let retained = prompts.filter { $0.conversationID != conversationID || liveRecordIDs.contains($0.messageEventID) }
        guard retained.count != prompts.count else {
            return
        }
        thread.pendingPullRequestLinkPrompts = retained
        scheduleSave()
    }

    private func liveConversationRecordIDs() throws -> Set<String> {
        let conversationID = conversation.id
        let records = try modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.conversationId == conversationID }
            )
        )
        return Set(records.map(\.id))
    }

    private func postPullRequestLinkRequest(identifier: PullRequestIdentifier, threadID: PersistentIdentifier) {
        NotificationCenter.default.post(
            name: .pullRequestLinkRequested,
            object: nil,
            userInfo: [
                PullRequestLinkRequestNotificationKey.request: PullRequestLinkRequest(
                    identifier: identifier,
                    threadID: threadID
                )
            ]
        )
    }
}
