import Foundation
import SwiftData
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test
    func `revision change restart reviews the latest input in the same conversation and keeps prior history`() async throws {
        let historyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("review-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: historyRoot) }
        let fixture = try ReviewCoordinatorFixture(historyStore: ReviewTeamHistoryStore(rootDirectory: historyRoot))
        fixture.service.revisionResults = [
            .success(PullRequestRevision(status: .open, baseRefOid: "base", headRefOid: "head")),
            .success(PullRequestRevision(status: .open, baseRefOid: "base", headRefOid: "new-head"))
        ]
        try fixture.start()
        let originalTask = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.waitForCompletion(of: originalTask)
        let failed = try #require(fixture.coordinator.runs[fixture.conversation.id])
        #expect(failed.canRestart)
        #expect(failed.error == ReviewTeamError.revisionChanged.localizedDescription)
        #expect(failed.voteReports.count == 3)
        #expect(failed.history?.count == 7)
        var detail = try fixture.service.detailResult.get()
        detail.headRefOid = "new-head"
        fixture.service.detailResult = .success(detail)
        fixture.service.diffSnapshotResult = .success(try PullRequestDiffSnapshot.make(
            text: makeUnifiedDiffFixture(fileCount: 1), baseOID: "base", headOID: "new-head"
        ))

        NotificationCenter.default.post(name: .reviewTeamRestartRequested, object: nil, userInfo: [
            "conversationID": failed.conversationID, "runID": failed.id, "generation": failed.generation
        ])

        let fresh = try #require(fixture.coordinator.runs[failed.conversationID])
        #expect(fresh.id != failed.id && fresh.proposalID != failed.proposalID)
        #expect(fresh.conversationID == failed.conversationID && fresh.generation == failed.generation + 1)
        #expect(fresh.team == failed.team && fresh.criteria == failed.criteria)
        #expect(fresh.inspections.isEmpty && fresh.voteReports.isEmpty && fresh.accepted.isEmpty)
        #expect(fresh.attempts.isEmpty && fresh.failures.isEmpty && fresh.history == [])
        let replacementTask = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fresh.conversationID))
        try await fixture.waitForCompletion(of: replacementTask)
        let completed = try #require(try fixture.conversation.collectiveReviewRun())
        #expect(completed.phase == .staged && completed.headOID == "new-head")
        #expect(completed.inputHash != failed.inputHash)
        #expect(completed.history?.count == 7)
        let calls = await fixture.worker.calls
        #expect(calls.filter { $0.phase == "inspection" }.count == 6)
        #expect(calls.filter { $0.phase == "votes" }.count == 6)
        let previous = try restartTranscriptRun(fixture.conversation, runID: failed.id)
        #expect(previous.restartedRunID == fresh.id && !previous.canRestart)
        #expect(previous.history == failed.history && previous.voteReports == failed.voteReports)
        #expect(fixture.conversation.events.filter { $0.type == ConversationEventRecord.collectiveReviewRunType }.count == 2)
        #expect(try fixture.conversation.pullRequestReviewProposal()?.sourceRunID == fresh.id)
    }

    @Test
    func `restart captures current staged proposal edits instead of the failed run snapshot`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let failed = try restartableRun(fixture)
        let proposal = PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: UUID().uuidString, deduplicationKey: "edited-proposal", repositoryNameWithOwner: "octo/alpha", number: 7,
            event: "comment", body: "Keep this edited summary.", comments: [], titleSnapshot: "Current proposal",
            pendingCommentCountSnapshot: 0, sourceHarnessID: "codex", sourceProcessToken: nil, sourceRequestID: nil, createdAt: .now
        )
        try fixture.conversation.storePullRequestReviewProposal(proposal)
        PullRequestReviewProposalEditState.recordEdit(proposalID: proposal.id)
        try fixture.container.mainContext.save()
        let expected = try fixture.coordinator.staging.snapshot(
            for: failed.identifier, editState: PullRequestReviewProposalEditState.current(proposalID: proposal.id)
        )

        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)

        let fresh = try #require(fixture.coordinator.runs[failed.conversationID])
        #expect(failed.priorProposal.proposalID == nil)
        #expect(fresh.priorProposal == expected)
        let task = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fresh.conversationID))
        try await fixture.waitForCompletion(of: task)
        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .staged)
        let replacement = try #require(try fixture.conversation.pullRequestReviewProposal())
        #expect(replacement.id != proposal.id)
        #expect(replacement.body == proposal.body)
    }

    @Test
    func `restart rejects stale identities and duplicate clicks against persisted and active runs`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let failed = try restartableRun(fixture)
        fixture.coordinator.restart(conversationID: failed.conversationID, runID: "older-run", generation: failed.generation)
        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation + 1)
        var newer = failed
        newer.generation += 1
        try fixture.conversation.storeCollectiveReviewRun(newer)
        try fixture.container.mainContext.save()
        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)
        fixture.coordinator.restart(conversationID: newer.conversationID, runID: newer.id, generation: newer.generation)
        #expect(try fixture.conversation.collectiveReviewRun()?.generation == newer.generation)
        let otherRun = try fixture.makeRun()
        try fixture.conversation.storeCollectiveReviewRun(otherRun)
        try fixture.container.mainContext.save()
        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)
        #expect(try fixture.conversation.collectiveReviewRun()?.id == otherRun.id)
        #expect(fixture.coordinator.scheduledTaskForTesting(conversationID: failed.conversationID) == nil)
        #expect(await fixture.worker.calls.isEmpty)
        try fixture.coordinator.persist(newer)

        fixture.coordinator.restart(conversationID: newer.conversationID, runID: newer.id, generation: newer.generation)
        let fresh = try #require(fixture.coordinator.runs[newer.conversationID])
        fixture.coordinator.restart(conversationID: newer.conversationID, runID: newer.id, generation: newer.generation)

        #expect(fixture.coordinator.runs[newer.conversationID]?.id == fresh.id)
        #expect(fixture.conversation.events.filter { $0.type == ConversationEventRecord.collectiveReviewRunType }.count == 2)
        let task = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fresh.conversationID))
        try await fixture.waitForCompletion(of: task)
        #expect(await fixture.worker.inspectionCount == 3)
    }

    @Test
    func `failed restart save preserves the old run and transcript without launching workers`() async throws {
        let saves = ReviewRestartSaveControl()
        let fixture = try ReviewCoordinatorFixture(commitSave: saves.save)
        let failed = try restartableRun(fixture)
        let priorJSON = fixture.conversation.pullRequestReviewRunJSON
        let priorEvent = try #require(fixture.conversation.events.first { $0.type == ConversationEventRecord.collectiveReviewRunType })
        let priorContent = priorEvent.content
        saves.shouldFail = true

        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)

        #expect(fixture.conversation.pullRequestReviewRunJSON == priorJSON)
        #expect(priorEvent.content == priorContent)
        #expect(fixture.conversation.events.filter { $0.type == ConversationEventRecord.collectiveReviewRunType }.count == 1)
        #expect(fixture.coordinator.runs[failed.conversationID]?.canRestart == true)
        #expect(fixture.coordinator.scheduledTaskForTesting(conversationID: failed.conversationID) == nil)
        #expect(await fixture.worker.calls.isEmpty)
        #expect(!fixture.container.mainContext.hasChanges)
        let readContext = ModelContext(fixture.container)
        let saved = try #require(readContext.resolveConversation(conversationID: failed.conversationID))
        #expect(saved.pullRequestReviewRunJSON == priorJSON)
        #expect(try restartTranscriptRun(saved, runID: failed.id).restartedRunID == nil)
    }

    @Test
    func `restart recovers a displayed cancellation failure after storage becomes available`() async throws {
        let saves = ReviewRestartSaveControl()
        let fixture = try ReviewCoordinatorFixture(commitSave: saves.save)
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        let pipeline = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.withPipelineCleanup(pipeline, gate: gate) {
            try await fixture.wait { await fixture.worker.inspectionCount == 3 }
            let cancellationRoot = fixture.packetRoot.appendingPathComponent("cancellations")
            try Data().write(to: cancellationRoot)
            saves.shouldFail = true
            fixture.coordinator.cancel(conversationID: fixture.conversation.id)
            let displayed = try #require(fixture.coordinator.runs[fixture.conversation.id])
            let persisted = try #require(try fixture.conversation.collectiveReviewRun())
            #expect(displayed.canRestart)
            #expect(persisted.phase == .inspecting && persisted.generation < displayed.generation)
            saves.shouldFail = false
            try FileManager.default.removeItem(at: cancellationRoot)

            fixture.coordinator.restart(
                conversationID: displayed.conversationID, runID: displayed.id, generation: displayed.generation
            )

            let fresh = try #require(fixture.coordinator.runs[displayed.conversationID])
            #expect(fresh.id != displayed.id && fresh.generation == displayed.generation + 1)
            let task = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fresh.conversationID))
            gate.open()
            try await fixture.waitForCompletion(of: pipeline)
            try await fixture.waitForCompletion(of: task)
            #expect(try fixture.conversation.collectiveReviewRun()?.phase == .staged)
            let previous = try restartTranscriptRun(fixture.conversation, runID: displayed.id)
            #expect(previous.phase == .failed && previous.restartedRunID == fresh.id)
            #expect(await fixture.worker.inspectionCount == 6)
        }
    }

    @Test
    func `restart cannot overlap an unfinished review for the same pull request`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let failed = try restartableRun(fixture)
        let other = Conversation(id: UUID().uuidString, harness: "codex", thread: fixture.conversation.thread)
        fixture.container.mainContext.insert(other)
        let uppercase = PullRequestIdentifier(owner: "OCTO", repo: "ALPHA", number: failed.identifier.number)
        let unfinished = try fixture.makeRun(conversationID: other.id, identifier: uppercase)
        try fixture.coordinator.persist(unfinished)

        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)

        #expect(try fixture.conversation.collectiveReviewRun()?.id == failed.id)
        #expect(try restartTranscriptRun(fixture.conversation, runID: failed.id).restartedRunID == nil)
        #expect(fixture.coordinator.workingConversationIDs == [other.id])
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test(arguments: ["archived", "deleted"])
    func `restart cannot launch for unavailable conversations`(state: String) async throws {
        let fixture = try ReviewCoordinatorFixture()
        let failed = try restartableRun(fixture)
        if state == "archived" {
            fixture.conversation.thread?.archivedAt = .now
        } else {
            fixture.container.mainContext.delete(fixture.conversation)
        }
        try fixture.container.mainContext.save()

        fixture.coordinator.restart(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)

        #expect(fixture.coordinator.runs[failed.conversationID]?.id == failed.id)
        #expect(fixture.coordinator.scheduledTaskForTesting(conversationID: failed.conversationID) == nil)
        #expect(await fixture.worker.calls.isEmpty)
    }

    private func restartableRun(_ fixture: ReviewCoordinatorFixture) throws -> ReviewTeamRun {
        var run = try fixture.makeRun()
        run.phase = .failed
        run.requiresNewRun = true
        run.error = ReviewTeamError.revisionChanged.localizedDescription
        try fixture.coordinator.persist(run)
        return run
    }

    private func restartTranscriptRun(_ conversation: Conversation, runID: String) throws -> ReviewTeamRun {
        let event = try #require(conversation.events.first { $0.id == "collective-review-run:\(runID)" })
        let content = try #require(event.content)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReviewTeamRun.self, from: Data(content.utf8))
    }
}

@MainActor
private final class ReviewRestartSaveControl {
    var shouldFail = false

    func save(_ context: ModelContext) throws {
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
        try context.save()
    }
}
