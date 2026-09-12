import Foundation

extension ChatItemGrouper {
    func handleCollectiveReviewRun(_ event: ConversationEventRecord) {
        guard let item = collectiveReviewRunItem(event) else {
            return
        }
        collectiveReviewRunContentsByEventID[event.id] = event.content
        currentToolApprovalBatch = nil
        flushGroup()
        flushSubAgents()
        replaceOrAppendTranscriptItem(item)
    }

    /// A hidden task misses progress notifications; refresh mutable run rows without replaying ordinary provider events.
    func refreshCollectiveReviewRuns(in events: ArraySlice<ConversationEventRecord>) {
        for event in events where event.type == ConversationEventRecord.collectiveReviewRunType {
            guard collectiveReviewRunContentsByEventID[event.id] != event.content else { continue }
            collectiveReviewRunContentsByEventID[event.id] = event.content
            guard let index = items.firstIndex(where: { $0.id == event.id }),
                  let item = collectiveReviewRunItem(event) else { continue }
            if items[index] != item { items[index] = item }
        }
    }

    func handleCollectiveReviewProposal(_ event: ConversationEventRecord) {
        guard let payload = decodeCollectiveProposal(event.content),
              let reviewEvent = PullRequestHostToolRequestParser.reviewEvent(from: payload.event) else {
            return
        }
        let pending = pendingHostToolOutcomesByKey[payload.proposalID]
        let entry = HostToolWidgetEntry(
            id: event.id,
            toolName: event.toolName ?? HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            content: .pullRequestReviewProposal(
                PullRequestReviewProposalWidgetContent(
                    event: reviewEvent,
                    identifier: payload.identifier,
                    body: payload.body,
                    commentCount: payload.commentCount,
                    pendingCommentCount: payload.pendingCommentCount,
                    proposalID: payload.proposalID,
                    message: nil,
                    status: .pendingConfirmation
                )
            ),
            isComplete: true,
            outcomeKey: payload.proposalID,
            outcome: pending?.outcome,
            outcomeDefinitionID: pending?.definitionID,
            outcomeTitle: pending?.title
        )
        currentToolApprovalBatch = nil
        flushGroup()
        flushSubAgents()
        replaceOrAppendTranscriptItem(.hostToolWidget(id: event.id, entry: entry))
    }
}

extension ChatItem {
    /// Durable and live run snapshots must update the card's lifecycle flags together with its content.
    static func collectiveReviewRun(id: String, run: ReviewTeamRun) -> ChatItem {
        return .hostToolWidget(
            id: id,
            entry: HostToolWidgetEntry(
                id: id,
                toolName: ConversationEventRecord.collectiveReviewRunType,
                content: .collectiveReviewRun(run),
                isComplete: !run.phase.isWorking,
                isInterrupted: run.phase == .interrupted || run.phase == .cancelled,
                isError: run.phase == .failed
            )
        )
    }
}

private extension ChatItemGrouper {
    func collectiveReviewRunItem(_ event: ConversationEventRecord) -> ChatItem? {
        guard let run = decodeCollectiveRun(event.content) else { return nil }
        return .collectiveReviewRun(id: event.id, run: run)
    }

    func decodeCollectiveRun(_ content: String?) -> ReviewTeamRun? {
        guard let content else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let run = try? decoder.decode(ReviewTeamRun.self, from: Data(content.utf8)),
              run.payloadVersion == 1 else {
            return nil
        }
        return run
    }

    func decodeCollectiveProposal(_ content: String?) -> ReviewProposalTranscriptPayload? {
        guard let content,
              let payload = try? JSONDecoder().decode(
                  ReviewProposalTranscriptPayload.self,
                  from: Data(content.utf8)
              ),
              payload.payloadVersion <= ReviewProposalTranscriptPayload.currentVersion else {
            return nil
        }
        return payload
    }
}
