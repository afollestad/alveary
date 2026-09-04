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

        let target = try await validatedDetail(
            for: request,
            reviewedRevision: reviewedDiffRevisions["\(context.conversationId.rawValue):\(request.identifier.displayKey)"]
        )
        let detail = target.detail

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
        // A proposal for this pull request opened by *another* conversation — an agentic review
        // runs in its own thread, so its propose would otherwise stand beside the card the user is
        // already looking at, and the pane would arbitrate between them by `createdAt`.
        try supersedeProposalsElsewhere(
            for: request.identifier,
            excluding: source.conversation,
            at: identity.requestDate
        )

        let record = makeRecord(
            request: request,
            target: target,
            identity: identity,
            requestID: requestID,
            providerID: context.providerId.rawValue
        )
        // Seeded — and awaited — before the envelope is stored: `pendingResult` posts the
        // lifecycle notification whose reload re-reads the cache, so the entry has to be on disk
        // by then or the proposing session's own card misses it and loads over the network. A
        // store that fails below leaves an orphan entry, which the next reload prunes.
        await seedPreviewCache(record: record, target: target, at: identity.requestDate)
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
    /// The validated pull request, plus the diff the anchor check parsed.
    ///
    /// The diff is carried out rather than discarded because the transcript card needs exactly
    /// these hunks, and refetching them there costs a second `gh pr diff` and a loading caption for
    /// a diff this call held moments earlier.
    struct ValidatedProposalTarget {
        let detail: PullRequestDetail
        /// Nil when the request staged no comments, so no diff was fetched.
        let diffFiles: [DiffFile]?
    }

    /// Fetches the pull request, applies the pane's own submission rules, and checks every staged
    /// comment's anchor against the live diff — all at propose time, so a proposal the user
    /// confirms cannot fail on a precondition the model could have seen.
    func validatedDetail(
        for request: PullRequestHostToolReviewProposalRequest,
        reviewedRevision: (base: String?, head: String?)?
    ) async throws -> ValidatedProposalTarget {
        let detail = try await fetchDetail(request.identifier)
        if let revision = reviewedRevision, revision.head != nil,
           revision.head != detail.headRefOid || revision.base != detail.baseRefOid {
            throw PullRequestDiffError.revisionChanged
        }
        try Self.validate(request, against: detail)
        guard !request.comments.isEmpty else {
            return ValidatedProposalTarget(detail: detail, diffFiles: nil)
        }
        let snapshot = try await pullRequestsService.fetchDiffSnapshot(request.identifier)
        if let head = snapshot.headOID, head != detail.headRefOid || snapshot.baseOID != detail.baseRefOid {
            throw PullRequestDiffError.revisionChanged
        }
        let paths = Set(request.comments.map(\.path))
        let diffFiles = try await Task.detached { try snapshot.parsedFiles(paths: paths) }.value
        try Self.validateAnchors(request.comments, against: diffFiles)
        return ValidatedProposalTarget(detail: detail, diffFiles: diffFiles)
    }

    /// Hands the transcript card the hunks this call already parsed, so it paints its comments on
    /// first appearance instead of refetching the same diff behind a loading caption.
    ///
    /// Narrowed through `ReviewProposalDiffNarrowing` because the card's own refresh narrows the
    /// same way; a seeded entry that disagreed would make the card re-flow when the refresh landed.
    /// Best-effort throughout — a cache that never fills only costs the card its usual load.
    func seedPreviewCache(
        record: PullRequestReviewProposalRecord,
        target: ValidatedProposalTarget,
        at date: Date
    ) async {
        guard let cache = reviewProposalPreviewCache,
              let identifier = record.identifier else {
            return
        }
        let files: [DiffFile]
        let hiddenFileCount: Int
        if let diffFiles = target.diffFiles {
            let narrowed = ReviewProposalDiffNarrowing.narrowed(
                files: diffFiles,
                linesByPath: ReviewProposalDiffNarrowing.linesByPath(for: record.stagedComments)
            )
            files = Array(narrowed.prefix(ReviewProposalDiffNarrowing.maximumFiles))
            hiddenFileCount = narrowed.count - files.count
        } else {
            // No staged comments. Seeding empty is only right when the user holds no draft of their
            // own either, because those threads are server state this call never fetched — the card
            // would paint "summary only" over comments the refresh is about to reveal.
            guard target.detail.pendingCommentCount == 0 else {
                return
            }
            files = []
            hiddenFileCount = 0
        }
        let entry = PullRequestReviewProposalPreviewCache.Entry(
            identifier: identifier,
            files: files,
            hiddenFileCount: hiddenFileCount,
            viewerLogin: target.detail.viewerLogin,
            viewerAvatarURL: target.detail.viewerAvatarURL,
            viewerIsAuthor: target.detail.viewerLogin.map { $0 == target.detail.authorLogin } ?? false,
            fetchedAt: date
        )
        await cache.save(entry, forProposalID: record.id)
    }

    /// The stored envelope: everything the card renders and the confirmed submission publishes,
    /// including the staged comments.
    ///
    /// `target` carries the diff `validatedDetail` already parsed, so each comment keeps a
    /// fingerprint of the line it was written against; without one it can never relocate after a
    /// later commit moves it.
    func makeRecord(
        request: PullRequestHostToolReviewProposalRequest,
        target: ValidatedProposalTarget,
        identity: PullRequestHostToolCallIdentity,
        requestID: String,
        providerID: String
    ) -> PullRequestReviewProposalRecord {
        let detail = target.detail
        let diffFiles = target.diffFiles ?? []
        return PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: makeProposalID(),
            deduplicationKey: identity.deduplicationKey,
            repositoryNameWithOwner: request.identifier.nameWithOwner,
            number: request.identifier.number,
            event: PullRequestHostToolRequestParser.reviewEventName(for: request.event),
            body: request.body,
            comments: request.comments.isEmpty ? nil : request.comments.map { comment in
                let fingerprint = ReviewProposalAnchorResolution.fingerprint(
                    path: comment.path,
                    line: comment.line,
                    side: comment.side == .left ? .left : .right,
                    in: diffFiles
                )
                return PullRequestReviewProposalRecord.Comment(
                    path: comment.path,
                    line: comment.line,
                    side: comment.side.rawValue,
                    body: comment.body,
                    anchorContent: fingerprint?.content,
                    anchorContext: fingerprint?.context
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
    ///
    /// The match runs through `FlattenedDiffPreviewRows.commentAnchor(for:path:)`, the pane's own
    /// mapping, rather than comparing line numbers directly. A context line carries *both*
    /// numbers, so a raw `oldLineNumber` comparison accepts a LEFT anchor on one — which the pane
    /// then cannot draw, because it only ever anchors a context line RIGHT. Sharing the mapping is
    /// what keeps a confirmable proposal renderable.
    static func validateAnchors(
        _ comments: [PullRequestHostToolReviewCommentItem],
        against files: [DiffFile]
    ) throws {
        for (index, comment) in comments.enumerated() {
            let target = DiffCommentAnchor(
                path: comment.path,
                side: comment.side == .left ? .left : .right,
                line: comment.line
            )
            let anchored = files.contains { file in
                file.path == comment.path && file.hunks.contains { hunk in
                    hunk.lines.contains { line in
                        FlattenedDiffPreviewRows.commentAnchor(for: line, path: comment.path) == target
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

    /// Resolves every other conversation's pending proposal for this pull request, so one pull
    /// request has one live confirmation. `resolvedAgainstExisting` already enforces that within a
    /// conversation; this extends it across them, because a thread's envelope is invisible to any
    /// other thread's `propose_pr_review`.
    ///
    /// The model is expected to have read `get_pr_review_proposal` and carried forward whatever it
    /// meant to keep — that tool exists so this supersede cannot silently discard the user's staged
    /// comments — and each superseded card resolves in its own transcript rather than being
    /// orphaned.
    func supersedeProposalsElsewhere(
        for identifier: PullRequestIdentifier,
        excluding conversation: Conversation,
        at requestDate: Date
    ) throws {
        guard let conversations = try? modelContext.fetch(
            PullRequestReviewProposalLookup.proposalHoldingConversations
        ) else {
            return
        }
        let others = conversations.filter { $0.id != conversation.id }
        for owner in PullRequestReviewProposalLookup.proposals(in: others, for: identifier) {
            guard let source = modelContext.resolveConversation(conversationID: owner.conversationID) else {
                continue
            }
            try supersede(owner.record, on: source, at: requestDate)
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
        } else if record.body != nil {
            // Said outright, because the model echoes this message to the user and the "Comment"
            // verdict's name collides with "inline comment" — without this clause a summary-only
            // proposal gets narrated as though a comment were staged.
            message += ", publishing the review summary only — no inline comments are staged"
        } else {
            // A bodyless approve has no summary to publish, so claiming one would be its own lie.
            message += " with no inline comments staged"
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
            // GitHub's verdict is named "Comment", which collides with inline comments; naming it
            // as a review kind keeps "leave a review comment" from implying one was staged.
            "submit a \"Comment\" review"
        }
    }
}
