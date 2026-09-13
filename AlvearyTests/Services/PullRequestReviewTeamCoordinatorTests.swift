import Foundation
import SwiftData
import Testing

@testable import Alveary

@MainActor
struct PullRequestReviewTeamCoordinatorTests {
    @Test
    func `starting before recovery cannot replace persisted unfinished work`() throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .interrupted
        try fixture.conversation.storeCollectiveReviewRun(run)
        try fixture.container.mainContext.save()
        #expect(fixture.coordinator.runs.isEmpty)
        #expect(throws: ReviewTeamError.self) { try fixture.start() }
        #expect(try fixture.conversation.collectiveReviewRun()?.id == run.id)
    }

    @Test
    func `recovery cancels archived work rather than leaving a phantom active task`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .interrupted
        fixture.conversation.thread?.archivedAt = .now
        try fixture.coordinator.persist(run)
        fixture.coordinator.recover()
        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .cancelled)
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `incomplete diff fails before worker execution`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        fixture.service.diffSnapshotResult = .success(try PullRequestDiffSnapshot.make(
            text: "", baseOID: "base", headOID: "head"
        ))
        try fixture.start()
        #expect(try await fixture.terminalRun().phase == .failed)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `diff content inconsistent with its index cannot reach workers`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let snapshot = try #require(try fixture.service.diffSnapshotResult?.get())
        let changed = makeUnifiedDiffFixture(fileCount: 1).replacingOccurrences(of: "File0", with: "File1")
        #expect(changed.utf8.count == snapshot.byteCount)
        try Data(changed.utf8).write(to: snapshot.url)
        try fixture.start()
        #expect(try await fixture.terminalRun().phase == .failed)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `archiving a failed run prevents retry`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .failed
        try fixture.coordinator.persist(run)
        fixture.conversation.thread?.archivedAt = .now
        try fixture.container.mainContext.save()
        fixture.coordinator.retry(conversationID: run.conversationID)
        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .failed)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `retry cannot overlap another unfinished run for the same pull request`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var failed = try fixture.makeRun()
        failed.phase = .failed
        try fixture.coordinator.persist(failed)
        let other = Conversation(id: "newer-run", provider: "codex", thread: fixture.conversation.thread)
        fixture.container.mainContext.insert(other)
        let unfinished = try fixture.makeRun(conversationID: other.id)
        try fixture.coordinator.persist(unfinished)

        fixture.coordinator.retry(conversationID: failed.conversationID)

        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .failed)
        #expect(try fixture.conversation.collectiveReviewRun()?.generation == failed.generation)
        #expect(fixture.coordinator.workingConversationIDs == [other.id])
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `a conflict requiring new input cannot restart the frozen run`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .failed
        run.requiresNewRun = true
        try fixture.coordinator.persist(run)
        fixture.coordinator.retry(conversationID: run.conversationID)
        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .failed)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `staging receipt prevents recreation and repairs superseded outcomes once`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let owner = Conversation(id: "old-owner", provider: "codex", thread: fixture.conversation.thread)
        fixture.container.mainContext.insert(owner)
        var run = try fixture.makeRun(prior: PullRequestCollectiveReviewStagingSnapshot(
            proposalOwnerConversationID: owner.id, proposalID: "old-proposal", proposalContentHash: "old-content", editState: nil
        ))
        run.phase = .staged
        run.resultHash = "terminal-receipt"
        run.supersededProposalIDs = ["old-proposal"]
        try fixture.coordinator.persist(run)
        fixture.coordinator.recover()
        fixture.coordinator.repairSupersededOutcome(run)
        #expect(await fixture.worker.calls.isEmpty)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(owner.events.filter { $0.type == ConversationEventRecord.hostToolOutcomeType && $0.toolId == "old-proposal" }.count == 1)
    }

    @Test
    func `interrupted corrective attempt resumes without spending another retry`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .interrupted
        run.attempts["inspecting:lead"] = 1
        run.failures["inspecting:lead"] = "Previous process failed"
        try fixture.coordinator.persist(run)
        fixture.coordinator.recover()
        let resumed = try await fixture.terminalRun()
        #expect(resumed.phase == .staged)
        #expect(resumed.generation == 1)
        #expect(resumed.attempts["inspecting:lead"] == 1)
        #expect(resumed.failures["inspecting:lead"] == nil)
        #expect(await fixture.worker.inspectionCount == 3)
    }

    @Test
    func `changed inspection on recovery resets downstream retry budgets`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        for member in run.team.prefix(2) {
            run.inspections[member.id] = ReviewInspectionReport(findings: [ReviewCandidate(
                id: "old-\(member.id)", priority: 2, path: "File0.swift", line: 1, side: "RIGHT",
                body: "A concrete problem.", evidence: "Concrete support."
            )])
        }
        run.canonical = ReviewCanonicalReport(findings: [ReviewCanonicalFinding(
            id: "old-finding", sourceCandidateIDs: run.team.prefix(2).map { "old-\($0.id)" },
            path: "File0.swift", line: 1, side: "RIGHT", body: "A concrete problem."
        )])
        run.attempts = ["inspecting:lead": 1, "consolidating:lead": 1, "crossChecking:lead": 2]
        run.failures["crossChecking:lead"] = "Old invalid response"
        try fixture.coordinator.persist(run)
        let input = try await fixture.coordinator.prepareInput(run)
        run.inputHash = input.lease.inputHash
        run.baseOID = input.detail.baseRefOid
        run.headOID = input.detail.headRefOid
        run.phase = .interrupted
        try fixture.coordinator.persist(run)

        fixture.coordinator.recover()

        let resumed = try await fixture.terminalRun()
        #expect(resumed.phase == .staged)
        #expect(resumed.attempts == ["inspecting:lead": 1])
        #expect(resumed.failures.isEmpty)
        #expect(await fixture.worker.inspectionCount == 1)
        #expect(resumed.voteReports.count == 3)
    }

    @Test
    func `cancelled runs never resume and archived tasks cannot launch`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .cancelled
        try fixture.coordinator.persist(run)
        fixture.coordinator.recover()
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(await fixture.worker.calls.isEmpty)
        fixture.conversation.thread?.archivedAt = .now
        try fixture.container.mainContext.save()
        #expect(throws: ReviewTeamError.missingConversation) { try fixture.start() }
    }

    @Test
    func `incomplete feedback fails preparation without invoking reviewers`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        fixture.service.reviewFeedbackResult = .failure(.decodingFailed("Incomplete published feedback"))
        try fixture.start()
        let result = try await fixture.terminalRun()
        #expect(result.phase == .failed)
        #expect(await fixture.worker.calls.isEmpty)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
    }

    @Test
    func `inspection runs concurrently with independent packets then stages one proposal`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let gate = PullRequestsServiceGate()
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        defer { gate.open() }
        try await fixture.wait { await fixture.worker.inspectionCount == 3 }
        #expect(fixture.coordinator.workingConversationIDs == [fixture.conversation.id])
        let initial = await fixture.worker.calls
        #expect(initial.allSatisfy { !$0.files.contains("candidates.json") && !$0.files.contains("canonical.json") })
        #expect(Set(initial.map(\.hash)).count == 1)
        gate.open()
        let run = try await fixture.terminalRun()
        #expect(run.phase == .staged)
        #expect(run.inspections.count == 3)
        #expect(run.voteReports.count == 3)
        #expect(run.accepted.first?.priority == 2)
        let proposal = try #require(try fixture.conversation.pullRequestReviewProposal())
        #expect(proposal.stagedComments.count == 1)
        #expect(proposal.stagedComments[0].body == "**[P2]** A concrete problem.")
        #expect(fixture.conversation.events.filter { $0.type == ConversationEventRecord.pullRequestReviewProposalType }.count == 1)
        #expect(fixture.service.submittedReviews.isEmpty)
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
    }

    @Test
    func `one corrective retry repairs malformed output without exposing peer reports`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        await fixture.worker.configure(malformedFirst: true)
        try fixture.start()
        let run = try await fixture.terminalRun()
        #expect(run.phase == .staged)
        #expect(run.attempts["inspecting:lead"] == 1)
        let inspections = await fixture.worker.calls.filter { $0.phase == "inspection" }
        #expect(inspections.count == 4)
        #expect(inspections.allSatisfy { $0.files == inspections.first?.files })
    }

    @Test
    func `cancellation invalidates the generation before late results arrive`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        let pipeline = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.withPipelineCleanup(pipeline, gate: gate) {
            try await fixture.wait { await fixture.worker.inspectionCount == 3 }
            let oldGeneration = try #require(fixture.coordinator.runs[fixture.conversation.id]?.generation)
            fixture.coordinator.cancel(conversationID: fixture.conversation.id)
            #expect(fixture.coordinator.runs[fixture.conversation.id]?.generation == oldGeneration + 1)
            gate.open()
            try await fixture.waitForCompletion(of: pipeline)
            #expect(await fixture.worker.completedCount == 3)
            #expect(try fixture.conversation.collectiveReviewRun()?.phase == .cancelled)
            #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
            #expect(fixture.conversation.events.allSatisfy { $0.type != ConversationEventRecord.pullRequestReviewProposalType })
        }
    }

    @Test
    func `own PR empty results complete durably without a proposal or voting`() async throws {
        let fixture = try ReviewCoordinatorFixture(ownPR: true)
        await fixture.worker.configure(empty: true)
        try fixture.start()
        let run = try await fixture.terminalRun()
        #expect(run.phase == .completed)
        #expect(run.voteReports.isEmpty)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        #expect(await fixture.worker.calls.count == 3)
        fixture.coordinator.recover()
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
    }

    @Test
    func `own PR with existing pending feedback stages a comment review`() async throws {
        let fixture = try ReviewCoordinatorFixture(ownPR: true)
        var detail = try fixture.service.detailResult.get()
        detail.reviewThreads = [makeReviewThread(nodeID: "PENDING", path: "File0.swift", line: 1, isPending: true)]
        fixture.service.detailResult = .success(detail)
        await fixture.worker.configure(empty: true)
        try fixture.start()
        let run = try await fixture.terminalRun()
        #expect(run.phase == .staged)
        #expect(try fixture.conversation.pullRequestReviewProposal()?.event == "comment")
    }

    @Test
    func `partial failures require the original quorum and retry reuses complete inspections`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        await fixture.worker.configure(failedInspectors: ["peer-1", "peer-2"])
        try fixture.start()
        let failed = try await fixture.terminalRun()
        #expect(failed.phase == .failed)
        #expect(failed.inspections.count == 1)
        #expect(failed.requiredVotes == 2)
        await fixture.worker.configure()
        fixture.coordinator.retry(conversationID: fixture.conversation.id)
        let result = try await fixture.terminalRun()
        #expect(result.phase == .staged)
        #expect(await fixture.worker.calls.filter { $0.phase == "inspection" && $0.memberID == "lead" }.count == 1)
    }

    @Test
    func `changed packet invalidates accepted findings before a no candidates rerun`() async throws {
        let fixture = try ReviewCoordinatorFixture(ownPR: true)
        await fixture.worker.configure(empty: true)
        var run = try fixture.makeRun()
        run.inputHash = "old-packet"
        run.accepted = [ReviewAcceptedFinding(finding: ReviewCoordinatorWorker.canonicalFinding, priority: 0, votes: [])]
        try fixture.coordinator.persist(run)
        try await fixture.coordinator.perform(conversationID: run.conversationID, generation: run.generation)
        #expect(try fixture.conversation.collectiveReviewRun()?.accepted.isEmpty == true)
        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .completed)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
    }

    @Test
    func `revision changes fail before cached reports are reused`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.headOID = "old-head"
        run.baseOID = "base"
        try fixture.coordinator.persist(run)
        await #expect(throws: ReviewTeamError.revisionChanged) {
            try await fixture.coordinator.perform(conversationID: run.conversationID, generation: run.generation)
        }
        #expect(await fixture.worker.calls.isEmpty)
    }
}
