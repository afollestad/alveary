import Foundation
import SwiftData
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test
    func `startup recovery does not replace workers started during discovery`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let gate = PullRequestsServiceGate()
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        defer { gate.open() }
        try await fixture.wait { await fixture.worker.inspectionCount == 3 }
        let original = try #require(fixture.coordinator.runs[fixture.conversation.id])

        fixture.coordinator.recover()

        #expect(fixture.coordinator.runs[fixture.conversation.id] == original)
        gate.open()
        #expect(try await fixture.terminalRun().phase == .staged)
        #expect(await fixture.worker.inspectionCount == 3)
    }

    @Test
    func `cancellation receipt survives a failed database save and prevents relaunch execution`() async throws {
        let saves = ReviewCoordinatorSaveControl()
        let fixture = try ReviewCoordinatorFixture(commitSave: saves.save)
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        let pipeline = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.withPipelineCleanup(pipeline, gate: gate) {
            try await fixture.wait { await fixture.worker.inspectionCount == 3 }
            let original = try #require(fixture.coordinator.runs[fixture.conversation.id])
            let savedPhaseBeforeCancellation = try fixture.conversation.collectiveReviewRun()?.phase
            #expect(savedPhaseBeforeCancellation == .inspecting)
            #expect(fixture.coordinator.activity.blocksThreadCleanup(
                conversationID: original.conversationID, savedCollectivePhase: savedPhaseBeforeCancellation
            ))
            let priorJSON = fixture.conversation.pullRequestReviewRunJSON
            let priorEvents = fixture.conversation.events.map(\.content)
            saves.shouldFail = true

            fixture.coordinator.cancel(conversationID: original.conversationID)

            let savedPhaseAfterCancellation = try fixture.conversation.collectiveReviewRun()?.phase
            #expect(savedPhaseAfterCancellation == .inspecting)
            #expect(fixture.conversation.pullRequestReviewRunJSON == priorJSON)
            #expect(fixture.conversation.events.map(\.content) == priorEvents)
            #expect(!fixture.container.mainContext.hasChanges)
            let verificationContext = ModelContext(fixture.container)
            let persisted = try #require(verificationContext.resolveConversation(conversationID: original.conversationID))
            #expect(persisted.pullRequestReviewRunJSON == priorJSON)
            #expect(fixture.coordinator.runs[original.conversationID]?.phase == .cancelled)
            #expect(!fixture.coordinator.activity.blocksThreadCleanup(
                conversationID: original.conversationID, savedCollectivePhase: savedPhaseAfterCancellation
            ))
            #expect(fixture.coordinator.runs[original.conversationID]?.error?.contains("restored after relaunch") == true)
            let reopenedStore = ReviewTeamCancellationStore(rootDirectory: fixture.packetRoot.appendingPathComponent("cancellations"))
            #expect(try reopenedStore.contains(runID: original.id))
            #expect(try !fixture.coordinator.hasUnfinishedReview(for: original.identifier))
            saves.shouldFail = false
            let recovered = recoveryCoordinator(fixture, cancellationStore: reopenedStore)

            recovered.recover()

            #expect(try fixture.conversation.collectiveReviewRun()?.phase == .cancelled)
            #expect(try fixture.conversation.collectiveReviewRun()?.generation == original.generation + 1)
            #expect(try !reopenedStore.contains(runID: original.id))
            gate.open()
            try await fixture.waitForCompletion(of: pipeline)
            #expect(await fixture.worker.completedCount == 3)
            #expect(await fixture.worker.inspectionCount == 3)
            #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        }
    }

    @Test
    func `failed initial run save leaves no progress event or active work`() throws {
        let saves = ReviewCoordinatorSaveControl()
        let fixture = try ReviewCoordinatorFixture(commitSave: saves.save)
        saves.shouldFail = true

        #expect(throws: CocoaError.self) { try fixture.start() }

        #expect(fixture.conversation.pullRequestReviewRunJSON == nil)
        #expect(fixture.conversation.events.isEmpty)
        #expect(fixture.coordinator.runs.isEmpty)
        #expect(!fixture.container.mainContext.hasChanges)
        let verificationContext = ModelContext(fixture.container)
        let persisted = try #require(verificationContext.resolveConversation(conversationID: fixture.conversation.id))
        #expect(persisted.pullRequestReviewRunJSON == nil)
        #expect(persisted.events.isEmpty)
    }

    @Test(arguments: [false, true])
    func `failed terminal save never notifies completion`(ownPR: Bool) async throws {
        let fixture = try ReviewCoordinatorFixture(ownPR: ownPR, commitSave: { context in
            let conversations = try context.fetch(FetchDescriptor<Conversation>())
            let phases = try conversations.compactMap { try $0.collectiveReviewRun()?.phase }
            if phases.contains(.staged) || phases.contains(.completed) {
                throw CocoaError(.fileWriteUnknown)
            }
            try context.save()
        })
        await fixture.worker.configure(empty: ownPR)

        try fixture.start()

        #expect(try await fixture.terminalRun().phase == .failed)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        #expect(fixture.conversation.events.allSatisfy { $0.type != ConversationEventRecord.pullRequestReviewProposalType })
        #expect(fixture.notificationManager.handleEventCalls.isEmpty)
    }

    @Test
    func `staging replay and relaunch do not repeat a proposal notification`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        try fixture.start()
        let pipeline = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.waitForCompletion(of: pipeline)
        let run = try #require(try fixture.conversation.collectiveReviewRun())
        let proposal = try #require(try fixture.conversation.pullRequestReviewProposal())
        let event = try #require(PullRequestReviewEvent(rawValue: proposal.event.uppercased()))
        let base = try #require(run.baseOID)
        let head = try #require(run.headOID)
        #expect(fixture.notificationManager.handleEventCalls.count == 1)
        let request = PullRequestCollectiveReviewStagingService.Request(
            runID: run.id, proposalID: run.proposalID, sourceConversationID: run.conversationID,
            identifier: run.identifier, reviewedBaseOID: base, reviewedHeadOID: head, event: event, body: proposal.body,
            acceptedFindings: run.accepted, team: run.team, expectedSnapshot: run.priorProposal
        )

        let receipt = try await fixture.coordinator.staging.stage(request, lateEditState: { nil }, atomicallyMutateRun: { _, _ in
            Issue.record("An exact replay must not mutate the run.")
        })
        let recovered = recoveryCoordinator(fixture, cancellationStore: fixture.coordinator.cancellationStore)
        recovered.recover()

        #expect(receipt.proposalID == proposal.id)
        #expect(recovered.runs[run.conversationID]?.phase == .staged)
        #expect(fixture.notificationManager.handleEventCalls.count == 1)
    }

    @Test
    func `unreadable cancellation storage blocks automatic recovery`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.history = [ReviewTeamAttempt(
            id: "attempt", reviewerID: "lead", phase: .inspecting, generation: 0, startedAt: .now, packetHash: "packet",
            prompt: ReviewHistoryArtifact(id: "prompt", name: "prompt.txt", byteCount: 0), inputs: [], status: .running
        )]
        try fixture.coordinator.persist(run)
        let root = fixture.packetRoot.appendingPathComponent("cancellations")
        try FileManager.default.createDirectory(at: fixture.packetRoot, withIntermediateDirectories: true)
        try Data("invalid directory".utf8).write(to: root)

        fixture.coordinator.recover()

        let recovered = try #require(fixture.coordinator.runs[run.conversationID])
        #expect(recovered.phase == .failed)
        #expect(recovered.requiresNewRun == true)
        #expect(recovered.error?.contains("Could not verify saved cancellation") == true)
        #expect(recovered.history?.first?.status == .interrupted)
        #expect(recovered.history?.first?.finishedAt != nil)
        #expect(fixture.coordinator.failedConversationIDs == [run.conversationID])
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `a failed run restored at launch reports failure`() throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .failed
        run.error = ReviewTeamError.revisionChanged.localizedDescription
        run.requiresNewRun = true
        try fixture.coordinator.persist(run)
        let relaunched = recoveryCoordinator(fixture, cancellationStore: fixture.coordinator.cancellationStore)
        #expect(relaunched.failedConversationIDs.isEmpty)

        relaunched.recover()

        #expect(relaunched.failedConversationIDs == [run.conversationID])
        #expect(relaunched.workingConversationIDs.isEmpty)
    }

    @Test
    func `an interrupted run whose resume cannot be saved reports failure`() async throws {
        let saves = ReviewCoordinatorSaveControl()
        let fixture = try ReviewCoordinatorFixture(commitSave: saves.save)
        var run = try fixture.makeRun()
        run.phase = .interrupted
        try fixture.coordinator.persist(run)
        saves.shouldFail = true

        fixture.coordinator.recover()

        #expect(fixture.coordinator.runs[run.conversationID]?.phase == .interrupted)
        #expect(fixture.coordinator.runs[run.conversationID]?.error != nil)
        #expect(fixture.coordinator.failedConversationIDs == [run.conversationID])
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `recovering an older cancelled run preserves the newer review reservation`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let old = try fixture.makeRun()
        try fixture.coordinator.persist(old)
        try fixture.coordinator.cancellationStore.record(runID: old.id)
        let newerConversation = Conversation(id: "newer-review", harness: "codex", thread: fixture.conversation.thread)
        fixture.container.mainContext.insert(newerConversation)
        try fixture.container.mainContext.save()
        let gate = PullRequestsServiceGate()
        await fixture.worker.configure(gate: gate)
        try fixture.coordinator.begin(conversationID: newerConversation.id, identifier: old.identifier,
                                      url: old.url, team: old.team, criteria: old.criteria)
        defer { gate.open() }
        try await fixture.wait { await fixture.worker.inspectionCount == 3 }

        fixture.coordinator.recover()

        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .cancelled)
        #expect(fixture.coordinator.workingConversationIDs == [newerConversation.id])
        #expect(fixture.coordinator.activity.isWorking(old.identifier, kind: .review))
        gate.open()
        try await fixture.wait { fixture.coordinator.runs[newerConversation.id]?.phase == .staged }
        #expect(await fixture.worker.inspectionCount == 3)
    }

    private func recoveryCoordinator(
        _ fixture: ReviewCoordinatorFixture, cancellationStore: ReviewTeamCancellationStore
    ) -> PullRequestReviewTeamCoordinator {
        PullRequestReviewTeamCoordinator(
            modelContext: fixture.container.mainContext, service: fixture.service, worker: fixture.worker, packets: fixture.packets,
            staging: fixture.coordinator.staging, activity: fixture.coordinator.activity, resolver: fixture.coordinator.resolver,
            cancellationStore: cancellationStore, notificationManager: fixture.notificationManager
        )
    }
}

@MainActor
private final class ReviewCoordinatorSaveControl {
    var shouldFail = false

    func save(_ context: ModelContext) throws {
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
        try context.save()
    }
}
