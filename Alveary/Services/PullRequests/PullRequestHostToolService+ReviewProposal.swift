import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Opens a review submission for the user to confirm. Nothing reaches GitHub here — the
    /// review's inline comments are staged inside the stored envelope, and confirming is what
    /// writes and publishes them.
    ///
    /// Submitting a review publishes a verdict and every comment attached to it, and GitHub
    /// offers no way to take that back — the one pull request action that needs the user, which is
    /// why this mirrors `propose_scheduled_task` rather than the immediate tools beside it.
    func proposeReview(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        let source = try resolveSource(context: context)
        let request = try parseReviewProposal(arguments: arguments)
        let requestID = try requireRequestID(context)
        let identity = try callIdentity(
            context: context,
            source: source,
            canonicalPayloadHash: request.canonicalPayloadHash
        )
        if let receipt = try replayedReceipt(on: source.conversation, identity: identity) {
            return replayedResult(receipt: receipt, fields: Self.echoFields(request))
        }

        let detail = try await validatedDetail(for: request)

        if let existing = try existingProposal(on: source.conversation) {
            if let result = try resolvedAgainstExisting(
                existing,
                request: request,
                source: source,
                identity: identity
            ) {
                return result
            }
        }

        let record = makeRecord(
            request: request,
            detail: detail,
            identity: identity,
            requestID: requestID,
            providerID: context.providerId.rawValue
        )
        return try pendingResult(
            source: source,
            identity: identity,
            record: record,
            pendingCommentCount: detail.pendingCommentCount,
            storingRecord: true
        )
    }
}

private extension PullRequestHostToolService {
    /// Fetches the pull request, applies the pane's own submission rules, and checks every staged
    /// comment's anchor against the live diff — all at propose time, so a proposal the user
    /// confirms cannot fail on a precondition the model could have seen.
    func validatedDetail(
        for request: PullRequestHostToolReviewProposalRequest
    ) async throws -> PullRequestDetail {
        let detail = try await fetchDetail(request.identifier)
        try Self.validate(request, against: detail)
        if !request.comments.isEmpty {
            try Self.validateAnchors(
                request.comments,
                against: DiffParser.parse(try await fetchDiff(request.identifier))
            )
        }
        return detail
    }

    /// The stored envelope: everything the card renders and the confirmed submission publishes,
    /// including the staged comments.
    func makeRecord(
        request: PullRequestHostToolReviewProposalRequest,
        detail: PullRequestDetail,
        identity: PullRequestHostToolCallIdentity,
        requestID: String,
        providerID: String
    ) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: makeProposalID(),
            deduplicationKey: identity.deduplicationKey,
            repositoryNameWithOwner: request.identifier.nameWithOwner,
            number: request.identifier.number,
            event: PullRequestHostToolRequestParser.reviewEventName(for: request.event),
            body: request.body,
            comments: request.comments.isEmpty ? nil : request.comments.map { comment in
                PullRequestReviewProposalRecord.Comment(
                    path: comment.path,
                    line: comment.line,
                    side: comment.side.rawValue,
                    body: comment.body
                )
            },
            titleSnapshot: detail.title,
            pendingCommentCountSnapshot: detail.pendingCommentCount,
            sourceProviderID: providerID,
            sourceProcessToken: identity.processToken.uuidString.lowercased(),
            sourceRequestID: requestID,
            createdAt: identity.requestDate
        )
    }

    /// A pending proposal already exists on this conversation. Returns a result when the new call
    /// should not open one, or `nil` once the old proposal has been superseded.
    func resolvedAgainstExisting(
        _ existing: PullRequestReviewProposalRecord,
        request: PullRequestHostToolReviewProposalRequest,
        source: HostToolCallSource,
        identity: PullRequestHostToolCallIdentity
    ) throws -> AgentCLIKit.AgentHostToolResult? {
        if existing.deduplicationKey == identity.deduplicationKey {
            // The provider replayed a call whose receipt has aged out; the proposal it opened is
            // still the live one, so report that rather than opening a second.
            return try pendingResult(
                source: source,
                identity: identity,
                record: existing,
                pendingCommentCount: existing.pendingCommentCountSnapshot
            )
        }
        guard existing.identifier == request.identifier else {
            throw PullRequestHostToolServiceError
                .proposalPendingForDifferentPullRequest(displayKey: existing.displayKey)
        }
        // A revised proposal for the same pull request replaces the unconfirmed one, so the
        // transcript never shows two live confirmations for one review.
        try supersede(existing, on: source.conversation, at: identity.requestDate)
        return nil
    }

    /// The same rules the pull request pane's footer enforces, checked before the user is asked, so
    /// a proposal the user confirms cannot fail on a precondition the model could have seen.
    static func validate(
        _ request: PullRequestHostToolReviewProposalRequest,
        against detail: PullRequestDetail
    ) throws {
        switch detail.status {
        case .merged, .closed:
            throw PullRequestHostToolServiceError.pullRequestNotReviewable(status: detail.status.rawValue)
        case .open, .draft:
            break
        }
        let isOwnPullRequest = detail.viewerLogin.map { $0 == detail.authorLogin } ?? false
        switch request.event {
        case .approve:
            guard !isOwnPullRequest else {
                throw PullRequestHostToolServiceError.cannotReviewOwnPullRequest
            }
        case .requestChanges:
            guard !isOwnPullRequest else {
                throw PullRequestHostToolServiceError.cannotReviewOwnPullRequest
            }
            guard request.body != nil else {
                throw PullRequestHostToolServiceError.reviewBodyRequired
            }
        case .comment:
            guard request.body != nil || !request.comments.isEmpty || detail.pendingCommentCount > 0 else {
                throw PullRequestHostToolServiceError.reviewCommentRequired
            }
        }
    }

    /// GitHub anchors a review comment to a line that appears in the diff — RIGHT to a new-side
    /// number, LEFT to an old-side one. A miss would fail at submission, after the user already
    /// confirmed, so it is refused here where the model can correct it.
    static func validateAnchors(
        _ comments: [PullRequestHostToolReviewCommentItem],
        against files: [DiffFile]
    ) throws {
        for (index, comment) in comments.enumerated() {
            let anchored = files.contains { file in
                file.path == comment.path && file.hunks.contains { hunk in
                    hunk.lines.contains { line in
                        comment.side == .left
                            ? line.oldLineNumber == comment.line
                            : line.newLineNumber == comment.line
                    }
                }
            }
            guard anchored else {
                throw PullRequestHostToolServiceError.reviewCommentAnchorInvalid(
                    index: index,
                    path: comment.path,
                    line: comment.line,
                    side: comment.side.rawValue
                )
            }
        }
    }

    func existingProposal(on conversation: Conversation) throws -> PullRequestReviewProposalRecord? {
        do {
            return try conversation.pullRequestReviewProposal()
        } catch {
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    /// Clears the old envelope, then records its rejection in a separate save. Folding the marker
    /// into the clearing save would let a marker write failure roll back the clear and strand two
    /// proposals; this way a failure leaves the old widget unresolved, never wrongly resolved.
    func supersede(
        _ record: PullRequestReviewProposalRecord,
        on conversation: Conversation,
        at requestDate: Date
    ) throws {
        conversation.clearPullRequestReviewProposal()
        try save()
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: record.id,
            sourceConversationID: conversation.id,
            outcome: .rejected,
            in: modelContext,
            at: requestDate
        )
        notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: nil)
    }

    /// The envelope and its receipt persist in one save: an exact retry must never be able to
    /// reopen a proposal the first call already opened.
    func pendingResult(
        source: HostToolCallSource,
        identity: PullRequestHostToolCallIdentity,
        record: PullRequestReviewProposalRecord,
        pendingCommentCount: Int,
        storingRecord: Bool = false
    ) throws -> AgentCLIKit.AgentHostToolResult {
        let message = Self.pendingMessage(record: record, pendingCommentCount: pendingCommentCount)
        do {
            if storingRecord {
                try source.conversation.storePullRequestReviewProposal(record)
            }
            try source.conversation.recordPullRequestHostToolReceipt(
                makeReceipt(
                    identity: identity,
                    toolName: PullRequestHostToolCatalog.proposeReviewToolName,
                    status: "pending_confirmation",
                    message: message,
                    handle: .proposal(record.id)
                )
            )
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PullRequestHostToolServiceError.persistenceFailure
        }
        if storingRecord {
            notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: nil)
        }

        return mutationResult(
            status: "pending_confirmation",
            message: message,
            fields: [
                "proposal_id": .string(record.id),
                "event": .string(record.event),
                "repository": .string(record.repositoryNameWithOwner),
                "number": .number(Double(record.number)),
                "comment_count": .number(Double(record.stagedComments.count)),
                "pending_comment_count": .number(Double(pendingCommentCount))
            ]
        )
    }

    static func echoFields(
        _ request: PullRequestHostToolReviewProposalRequest
    ) -> [String: AgentCLIKit.JSONValue] {
        [
            "event": .string(PullRequestHostToolRequestParser.reviewEventName(for: request.event)),
            "repository": .string(request.identifier.nameWithOwner),
            "number": .number(Double(request.identifier.number)),
            "comment_count": .number(Double(request.comments.count))
        ]
    }

    /// A plain-text-fallback provider has only this sentence to relay, so it has to say both what
    /// confirming would publish and that nothing has happened yet.
    static func pendingMessage(
        record: PullRequestReviewProposalRecord,
        pendingCommentCount: Int
    ) -> String {
        var message = "Opened a review confirmation in Alveary for \(record.displayKey): " +
            "\(verdictPhrase(record.event))"
        if !record.stagedComments.isEmpty {
            message += " with \(record.stagedComments.count) inline comment(s), staged in Alveary"
        }
        if pendingCommentCount > 0 {
            message += ", also publishing \(pendingCommentCount) already-pending draft comment(s)"
        }
        message += ". Nothing has been submitted — the user picks the verdict and confirms in " +
            "Alveary, and may reject it."
        return message
    }

    static func verdictPhrase(_ event: String) -> String {
        switch event {
        case "approve":
            "approve the pull request"
        case "request_changes":
            "request changes"
        default:
            "leave a review comment"
        }
    }
}
