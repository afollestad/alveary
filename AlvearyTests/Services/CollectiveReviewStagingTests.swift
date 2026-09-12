import Foundation
import SwiftData
import Testing

@testable import Alveary

@MainActor
struct CollectiveReviewStagingTests {
    @Test
    func `a failed save rolls back the exact prior proposal and receipt`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal(), failsSave: true)
        let before = fixture.prior.pullRequestReviewProposalJSON
        await #expect(throws: CollectiveStagingTestError.mutationFailed) {
            try await fixture.staging.stage(fixture.request(), lateEditState: { nil }, atomicallyMutateRun: { context, _ in
                context.resolveConversation(conversationID: fixture.source.id)?.pullRequestReviewRunJSON = "after"
            })
        }
        #expect(fixture.prior.pullRequestReviewProposalJSON == before)
        #expect(fixture.source.pullRequestReviewRunJSON == "before")
        #expect(try fixture.source.pullRequestReviewProposal() == nil)
        #expect(fixture.proposalEvents().isEmpty)
        #expect(fixture.source.events.allSatisfy { $0.type != ConversationEventRecord.pullRequestReviewProposalType })
        #expect(!fixture.context.hasChanges)
        let persisted = try fixture.persistedState()
        #expect(persisted.sourceRunJSON == "before")
        #expect(persisted.sourceProposalID == nil)
        #expect(persisted.priorProposalID == "prior-proposal")
        #expect(persisted.proposalEventCount == 0)
    }

    @Test
    func `a stale carried anchor leaves the prior proposal untouched`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal(), diff: "")
        await #expect(throws: ReviewTeamError.conflict) {
            try await fixture.staging.stage(fixture.request(), lateEditState: { nil }, atomicallyMutateRun: { _, _ in })
        }
        #expect(try fixture.prior.pullRequestReviewProposal()?.id == "prior-proposal")
        #expect(fixture.proposalEvents().isEmpty)
    }

    @Test
    func `late local edits and submissions block replacement`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal())
        let request = fixture.request()
        PullRequestReviewProposalEditState.beginSubmission(proposalID: "prior-proposal")
        defer { PullRequestReviewProposalEditState.endSubmission(proposalID: "prior-proposal") }
        await #expect(throws: ReviewTeamError.conflict) {
            try await fixture.staging.stage(request, lateEditState: {
                PullRequestReviewProposalEditState.current(proposalID: "prior-proposal")
            }, atomicallyMutateRun: { _, _ in })
        }
        #expect(try fixture.prior.pullRequestReviewProposal()?.id == "prior-proposal")
    }

    @Test
    func `own PR stages a comment even if a carried verdict requested changes`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal())
        var detail = try fixture.service.detailResult.get()
        detail.viewerLogin = detail.authorLogin
        fixture.service.detailResult = .success(detail)
        _ = try await fixture.staging.stage(fixture.request(), lateEditState: { nil }, atomicallyMutateRun: { _, _ in })
        #expect(try fixture.source.pullRequestReviewProposal()?.event == "comment")
    }

    @Test
    func `run mutation proposal swap and transcript event roll back together`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal())
        let request = fixture.request()

        await #expect(throws: CollectiveStagingTestError.mutationFailed) {
            try await fixture.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { context, _ in
                context.resolveConversation(conversationID: fixture.source.id)?.pullRequestReviewRunJSON = "after"
                throw CollectiveStagingTestError.mutationFailed
            })
        }

        #expect(fixture.source.pullRequestReviewRunJSON == "before")
        #expect(try fixture.source.pullRequestReviewProposal() == nil)
        #expect(try fixture.prior.pullRequestReviewProposal()?.id == "prior-proposal")
        #expect(fixture.proposalEvents().isEmpty)
        #expect(fixture.source.events.allSatisfy { $0.type != ConversationEventRecord.pullRequestReviewProposalType })
        #expect(!fixture.context.hasChanges)
        let persisted = try fixture.persistedState()
        #expect(persisted.sourceRunJSON == "before")
        #expect(persisted.sourceProposalID == nil)
        #expect(persisted.priorProposalID == "prior-proposal")
        #expect(persisted.proposalEventCount == 0)
    }

    @Test
    func `proposal content changed after snapshot stops staging`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal())
        let request = fixture.request()
        let changed = try #require(try fixture.prior.pullRequestReviewProposal()).appendingComment(
            PullRequestReviewProposalRecord.Comment(
                path: "File0.swift",
                line: 1,
                side: "RIGHT",
                body: "A human added this."
            )
        )
        try fixture.prior.storePullRequestReviewProposal(changed)
        try fixture.context.save()

        await #expect(throws: ReviewTeamError.conflict) {
            try await fixture.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { _, _ in })
        }

        #expect(try fixture.prior.pullRequestReviewProposal() == changed)
        #expect(try fixture.source.pullRequestReviewProposal() == nil)
        #expect(fixture.proposalEvents().isEmpty)
    }

    @Test
    func `carried comment relocates without changing identity fingerprint or evidence`() async throws {
        let evidence = PullRequestReviewProposalRecord.CommentEvidence(
            findingID: "old-finding",
            sourceCandidateIDs: ["old-candidate"],
            priority: 1,
            votes: [
                ReviewTeamVote(
                    voterID: "old-reviewer",
                    findingID: "old-finding",
                    decision: .agree,
                    priority: 1,
                    rationale: "Confirmed before this run."
                )
            ],
            reviewers: [
                PullRequestReviewProposalRecord.Reviewer(
                    id: "old-reviewer",
                    providerID: "old-provider",
                    modelOptionID: "old-model"
                )
            ]
        )
        let prior = makePriorProposal(body: "", evidence: evidence)
        let diff = """
        diff --git a/File0.swift b/File0.swift
        --- a/File0.swift
        +++ b/File0.swift
        @@ -1,0 +1,2 @@
        +inserted
        +line 0
        """ + "\n"
        let fixture = try CollectiveStagingFixture(prior: prior, diff: diff)
        let request = fixture.request(event: .requestChanges, body: "Generated blocker summary.", accepted: [])

        _ = try await fixture.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { context, _ in
            context.resolveConversation(conversationID: fixture.source.id)?.pullRequestReviewRunJSON = "staged"
        })

        let staged = try #require(try fixture.source.pullRequestReviewProposal())
        let comment = try #require(staged.stagedComments.first)
        #expect(comment.id == "prior-comment")
        #expect(comment.line == 2)
        #expect(comment.anchorContent == "line 0")
        #expect(comment.anchorContext == [])
        #expect(comment.body == "**[P1]** Existing issue.")
        #expect(comment.evidence == evidence)
        #expect(staged.event == "request_changes")
        #expect(staged.body == "Generated blocker summary.")
        #expect(try fixture.prior.pullRequestReviewProposal() == nil)
    }

    @Test
    func `exact replay returns the durable receipt without another mutation`() async throws {
        let fixture = try CollectiveStagingFixture()
        let request = fixture.request()
        var mutationCount = 0
        let first = try await fixture.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { context, _ in
            mutationCount += 1
            context.resolveConversation(conversationID: fixture.source.id)?.pullRequestReviewRunJSON = "staged"
        })

        fixture.source.clearPullRequestReviewProposal()
        try fixture.context.save()

        let replay = try await fixture.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { _, _ in
            mutationCount += 1
        })

        #expect(replay == first)
        #expect(mutationCount == 1)
        #expect(fixture.proposalEvents().count == 1)
        #expect(try fixture.source.pullRequestReviewProposal() == nil)
    }

    @Test(arguments: ["**[P0]** Existing issue.", "  [P1] Existing issue.\n", "Existing issue."])
    func `dedup ignores a carried priority prefix without rewriting the carried comment`(body: String) async throws {
        let prior = makePriorProposal(commentBody: body)
        let fixture = try CollectiveStagingFixture(prior: prior)
        let request = fixture.request(accepted: [makeAcceptedFinding(body: "Existing issue.")])

        _ = try await fixture.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { _, _ in })

        #expect(try fixture.source.pullRequestReviewProposal()?.stagedComments == prior.stagedComments)
    }

    @Test
    func `dedup keeps priority text inside distinct wording`() async throws {
        let fixture = try CollectiveStagingFixture(prior: makePriorProposal())
        let accepted = makeAcceptedFinding(body: "Keep [P1] Existing issue. visible.")

        _ = try await fixture.staging.stage(
            fixture.request(accepted: [accepted]), lateEditState: { nil }, atomicallyMutateRun: { _, _ in }
        )

        #expect(try fixture.source.pullRequestReviewProposal()?.stagedComments.map(\.body) == [
            "**[P1]** Existing issue.", "**[P2]** Keep [P1] Existing issue. visible."
        ])
    }
}

private enum CollectiveStagingTestError: Error, Equatable {
    case mutationFailed
    case missingConversation
}

@MainActor
private final class CollectiveStagingFixture {
    let container: ModelContainer
    let context: ModelContext
    let service: StubPullRequestsService
    let staging: PullRequestCollectiveReviewStagingService
    let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    let source: Conversation
    let prior: Conversation
    let snapshot: PullRequestCollectiveReviewStagingSnapshot

    init(
        prior priorProposal: PullRequestReviewProposalRecord? = nil,
        diff: String = makeUnifiedDiffFixture(fileCount: 1),
        failsSave: Bool = false
    ) throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        service = StubPullRequestsService()
        let thread = AgentThread(name: "Collective review")
        source = Conversation(id: "source", provider: "codex", thread: thread)
        prior = Conversation(id: "prior", provider: "codex", isMain: false, thread: thread)
        thread.conversations = [source, prior]
        context.insert(thread)
        source.pullRequestReviewRunJSON = "before"
        if let priorProposal {
            try prior.storePullRequestReviewProposal(priorProposal)
        }
        try context.save()

        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "bob"
        detail.baseRefOid = "base"
        detail.headRefOid = "head"
        service.detailResult = .success(detail)
        service.diffSnapshotResult = .success(
            try PullRequestDiffSnapshot.make(text: diff, baseOID: "base", headOID: "head")
        )
        staging = PullRequestCollectiveReviewStagingService(
            modelContext: context,
            service: service,
            now: { Date(timeIntervalSince1970: 2_000) },
            commitSave: { context in
                if failsSave { throw CollectiveStagingTestError.mutationFailed }
                try context.save()
            }
        )
        snapshot = try staging.snapshot(for: identifier, editState: nil)
    }

    func request(
        event: PullRequestReviewEvent = .approve,
        body: String? = nil,
        accepted: [ReviewAcceptedFinding] = [makeAcceptedFinding()]
    ) -> PullRequestCollectiveReviewStagingService.Request {
        PullRequestCollectiveReviewStagingService.Request(
            runID: "run",
            proposalID: "collective-proposal",
            sourceConversationID: source.id,
            identifier: identifier,
            reviewedBaseOID: "base",
            reviewedHeadOID: "head",
            event: event,
            body: body,
            acceptedFindings: accepted,
            team: makeCollectiveStagingTeam(),
            expectedSnapshot: snapshot
        )
    }

    func proposalEvents() -> [ConversationEventRecord] {
        (try? context.fetch(FetchDescriptor<ConversationEventRecord>()))?.filter {
            $0.type == ConversationEventRecord.pullRequestReviewProposalType
        } ?? []
    }

    func persistedState() throws -> CollectiveStagingPersistedState {
        let context = ModelContext(container)
        guard let source = context.resolveConversation(conversationID: self.source.id),
              let prior = context.resolveConversation(conversationID: self.prior.id) else {
            throw CollectiveStagingTestError.missingConversation
        }
        let proposalEvents = try context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.pullRequestReviewProposalType
        }
        return CollectiveStagingPersistedState(
            sourceRunJSON: source.pullRequestReviewRunJSON,
            sourceProposalID: try source.pullRequestReviewProposal()?.id,
            priorProposalID: try prior.pullRequestReviewProposal()?.id,
            proposalEventCount: proposalEvents.count
        )
    }
}

private struct CollectiveStagingPersistedState {
    let sourceRunJSON: String?
    let sourceProposalID: String?
    let priorProposalID: String?
    let proposalEventCount: Int
}

private func makePriorProposal(
    body: String? = "Please fix the existing blocker.",
    evidence: PullRequestReviewProposalRecord.CommentEvidence? = nil,
    commentBody: String = "**[P1]** Existing issue."
) -> PullRequestReviewProposalRecord {
    PullRequestReviewProposalRecord(
        payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
        id: "prior-proposal",
        deduplicationKey: "prior-request",
        repositoryNameWithOwner: "octo/alpha",
        number: 7,
        event: "request_changes",
        body: body,
        comments: [
            PullRequestReviewProposalRecord.Comment(
                id: "prior-comment",
                path: "File0.swift",
                line: 1,
                side: "RIGHT",
                body: commentBody,
                evidence: evidence,
                anchorContent: "line 0",
                anchorContext: []
            )
        ],
        titleSnapshot: "Prior title",
        pendingCommentCountSnapshot: 0,
        sourceProviderID: "codex",
        sourceProcessToken: "process",
        sourceRequestID: "request",
        sourceKind: .hostTool,
        reviewedBaseOID: "old-base",
        reviewedHeadOID: "old-head",
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
}

private func makeAcceptedFinding(body: String = "A concrete new issue.") -> ReviewAcceptedFinding {
    let finding = ReviewCanonicalFinding(
        id: "new-finding",
        sourceCandidateIDs: ["candidate"],
        path: "File0.swift",
        line: 1,
        side: "RIGHT",
        body: body
    )
    return ReviewAcceptedFinding(
        finding: finding,
        priority: 2,
        votes: makeCollectiveStagingTeam().map {
            ReviewTeamVote(
                voterID: $0.id,
                findingID: finding.id,
                decision: .agree,
                priority: 2,
                rationale: "Confirmed."
            )
        }
    )
}

private func makeCollectiveStagingTeam() -> [ReviewWorkerConfiguration] {
    (0..<3).map { index in
        ReviewWorkerConfiguration(
            id: index == 0 ? "lead" : "peer-\(index)",
            providerID: "codex",
            modelOptionID: "model-\(index)",
            launchModel: "model-\(index)",
            effort: "medium",
            executablePath: "/fake/codex"
        )
    }
}
