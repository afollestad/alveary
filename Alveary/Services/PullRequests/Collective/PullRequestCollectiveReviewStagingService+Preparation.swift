import Foundation

extension PullRequestCollectiveReviewStagingService {
    struct ResultDigest: Encodable {
        let runID: String
        let proposalID: String
        let identifier: PullRequestIdentifier
        let baseOID: String
        let headOID: String
        let event: String
        let body: String?
        let comments: [PullRequestReviewProposalRecord.Comment]
        let reviewers: [PullRequestReviewProposalRecord.Reviewer]
    }

    struct PreparedComments {
        let comments: [PullRequestReviewProposalRecord.Comment]
        let files: [DiffFile]
    }

    struct PreparedReview {
        let event: PullRequestReviewEvent
        let body: String?
        let comments: [PullRequestReviewProposalRecord.Comment]
        let resultHash: String
    }

    struct PreparedHandoff {
        let detail: PullRequestDetail
        let files: [DiffFile]
        let record: PullRequestReviewProposalRecord
        let receipt: HandoffReceipt
    }

    func prepareHandoff(_ request: Request) async throws -> PreparedHandoff {
        let prior = try priorProposal(for: request.expectedSnapshot)
        let detail = try await service.fetchDetail(request.identifier)
        try validateRevision(request, detail: detail)
        let preparedComments = try await stagedComments(request: request, prior: prior)
        let viewerIsAuthor = detail.viewerLogin.map { $0 == detail.authorLogin } ?? false
        let event = resolvedEvent(request.event, prior: prior, viewerIsAuthor: viewerIsAuthor)
        let priorBody = prior?.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = priorBody?.isEmpty == false ? prior?.body : request.body
        try validate(event: event, body: body, comments: preparedComments.comments, detail: detail)
        let hash = try resultHash(request: request, event: event, body: body, comments: preparedComments.comments)
        let review = PreparedReview(event: event, body: body, comments: preparedComments.comments, resultHash: hash)
        return PreparedHandoff(
            detail: detail,
            files: preparedComments.files,
            record: makeRecord(request: request, detail: detail, review: review),
            receipt: HandoffReceipt(
                proposalID: request.proposalID,
                resultHash: hash,
                supersededProposalIDs: prior.map { [$0.id] } ?? []
            )
        )
    }

    func validateRevision(_ request: Request, detail: PullRequestDetail) throws {
        guard detail.status == .open || detail.status == .draft else {
            throw PullRequestHostToolServiceError.pullRequestNotReviewable(status: detail.status.rawValue)
        }
        guard detail.baseRefOid == request.reviewedBaseOID,
              detail.headRefOid == request.reviewedHeadOID else {
            throw ReviewTeamError.revisionChanged
        }
    }

    func stagedComments(
        request: Request,
        prior: PullRequestReviewProposalRecord?
    ) async throws -> PreparedComments {
        let priorComments = prior?.stagedComments ?? []
        let paths = Set(priorComments.map(\.path) + request.acceptedFindings.map(\.finding.path))
        guard !paths.isEmpty else {
            return PreparedComments(comments: [], files: [])
        }
        let snapshot = try await service.fetchDiffSnapshot(request.identifier)
        guard snapshot.baseOID == request.reviewedBaseOID,
              snapshot.headOID == request.reviewedHeadOID else {
            throw ReviewTeamError.revisionChanged
        }
        let files = try await Task.detached { try snapshot.parsedFiles(paths: paths) }.value
        let carried = try carriedComments(priorComments, files: files)
        return try PreparedComments(
            comments: appendAccepted(
                request.acceptedFindings,
                to: carried,
                files: files,
                runID: request.runID,
                team: request.team
            ),
            files: files
        )
    }

    func carriedComments(
        _ comments: [PullRequestReviewProposalRecord.Comment],
        files: [DiffFile]
    ) throws -> [PullRequestReviewProposalRecord.Comment] {
        try zip(comments, ReviewProposalAnchorResolution.resolve(comments, against: files)).map { comment, resolution in
            let line: Int
            switch resolution {
            case .unchanged(let resolvedLine), .relocated(_, let resolvedLine):
                line = resolvedLine
            case .stale:
                throw ReviewTeamError.conflict
            }
            return PullRequestReviewProposalRecord.Comment(
                id: comment.id,
                path: comment.path,
                line: line,
                side: comment.side,
                body: comment.body,
                evidence: comment.evidence,
                anchorContent: comment.anchorContent,
                anchorContext: comment.anchorContext
            )
        }
    }

    func appendAccepted(
        _ accepted: [ReviewAcceptedFinding],
        to carried: [PullRequestReviewProposalRecord.Comment],
        files: [DiffFile],
        runID: String,
        team: [ReviewWorkerConfiguration]
    ) throws -> [PullRequestReviewProposalRecord.Comment] {
        var comments = carried
        var keys = Set(carried.map(duplicateKey))
        for acceptedFinding in accepted {
            let finding = acceptedFinding.finding
            let side = try reviewSide(finding.side)
            let body = "**[P\(acceptedFinding.priority)]** \(finding.body)"
            let key = duplicateKey(path: finding.path, line: finding.line, side: side.rawValue, body: body)
            guard keys.insert(key).inserted else {
                continue
            }
            guard let fingerprint = ReviewProposalAnchorResolution.fingerprint(
                path: finding.path,
                line: finding.line,
                side: side == .left ? .left : .right,
                in: files
            ) else {
                throw PullRequestHostToolServiceError.reviewCommentAnchorInvalid(
                    index: comments.count,
                    path: finding.path,
                    line: finding.line,
                    side: side.rawValue
                )
            }
            comments.append(PullRequestReviewProposalRecord.Comment(
                id: "collective:\(runID):\(finding.id)",
                path: finding.path,
                line: finding.line,
                side: side.rawValue,
                body: body,
                evidence: PullRequestReviewProposalRecord.CommentEvidence(
                    findingID: finding.id,
                    sourceCandidateIDs: finding.sourceCandidateIDs,
                    priority: acceptedFinding.priority,
                    votes: acceptedFinding.votes,
                    reviewers: reviewers(team)
                ),
                anchorContent: fingerprint.content,
                anchorContext: fingerprint.context
            ))
        }
        return comments
    }

    func reviewSide(_ value: String) throws -> PullRequestDiffSide {
        guard let side = PullRequestDiffSide(rawValue: value.uppercased()) else {
            throw ReviewTeamError.invalidOutput("A consolidated finding has an invalid diff side.")
        }
        return side
    }

    func duplicateKey(_ comment: PullRequestReviewProposalRecord.Comment) -> String {
        duplicateKey(path: comment.path, line: comment.line, side: comment.side, body: comment.body)
    }

    func duplicateKey(path: String, line: Int, side: String, body: String) -> String {
        // Priority is voted separately from wording; changing it must not repeat a carried finding.
        let wording = body.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: #"^(?:\*\*\[P[0-3]\]\*\*|\[P[0-3]\])(?:\s+|$)"#,
            with: "",
            options: .regularExpression
        )
        return "\(path)\u{0}\(line)\u{0}\(side.uppercased())\u{0}\(wording)"
    }

    func resolvedEvent(
        _ requested: PullRequestReviewEvent,
        prior: PullRequestReviewProposalRecord?,
        viewerIsAuthor: Bool
    ) -> PullRequestReviewEvent {
        guard !viewerIsAuthor else {
            return .comment
        }
        return prior?.event == "request_changes" ? .requestChanges : requested
    }

    func validate(
        event: PullRequestReviewEvent,
        body: String?,
        comments: [PullRequestReviewProposalRecord.Comment],
        detail: PullRequestDetail
    ) throws {
        let viewerIsAuthor = detail.viewerLogin.map { $0 == detail.authorLogin } ?? false
        if viewerIsAuthor && (event == .approve || event == .requestChanges) {
            throw PullRequestHostToolServiceError.cannotReviewOwnPullRequest
        }
        let hasBody = body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if event == .requestChanges, !hasBody {
            throw PullRequestHostToolServiceError.reviewBodyRequired
        }
        if event == .comment, !hasBody, comments.isEmpty, detail.pendingCommentCount == 0 {
            throw PullRequestHostToolServiceError.reviewCommentRequired
        }
    }

    func resultHash(
        request: Request,
        event: PullRequestReviewEvent,
        body: String?,
        comments: [PullRequestReviewProposalRecord.Comment]
    ) throws -> String {
        let digest = ResultDigest(
            runID: request.runID,
            proposalID: request.proposalID,
            identifier: request.identifier,
            baseOID: request.reviewedBaseOID,
            headOID: request.reviewedHeadOID,
            event: PullRequestHostToolRequestParser.reviewEventName(for: event),
            body: body,
            comments: comments,
            reviewers: reviewers(request.team)
        )
        return ReviewTeamDigest.hash(try ReviewTeamDigest.encode(digest))
    }

    func makeRecord(
        request: Request,
        detail: PullRequestDetail,
        review: PreparedReview
    ) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: request.proposalID,
            deduplicationKey: "collective-review:\(request.runID)",
            repositoryNameWithOwner: request.identifier.nameWithOwner,
            number: request.identifier.number,
            event: PullRequestHostToolRequestParser.reviewEventName(for: review.event),
            body: review.body,
            comments: review.comments.isEmpty ? nil : review.comments,
            titleSnapshot: detail.title,
            pendingCommentCountSnapshot: detail.pendingCommentCount,
            sourceProviderID: nil,
            sourceProcessToken: nil,
            sourceRequestID: nil,
            sourceKind: .collectiveReview,
            sourceRunID: request.runID,
            sourceResultHash: review.resultHash,
            reviewedBaseOID: request.reviewedBaseOID,
            reviewedHeadOID: request.reviewedHeadOID,
            reviewers: reviewers(request.team),
            createdAt: now()
        )
    }

    func reviewers(_ team: [ReviewWorkerConfiguration]) -> [PullRequestReviewProposalRecord.Reviewer] {
        team.map {
            PullRequestReviewProposalRecord.Reviewer(
                id: $0.id,
                providerID: $0.providerID,
                modelOptionID: $0.modelOptionID
            )
        }
    }

    func seedPreviewCache(
        record: PullRequestReviewProposalRecord,
        detail: PullRequestDetail,
        files: [DiffFile]
    ) async {
        await PullRequestReviewProposalPreparation.seedPreview(
            cache: previewCache, record: record, detail: detail,
            files: record.stagedComments.isEmpty ? nil : files, at: now()
        )
    }
}
