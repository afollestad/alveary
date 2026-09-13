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
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test
    func `recovering an older cancelled run preserves the newer review reservation`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let old = try fixture.makeRun()
        try fixture.coordinator.persist(old)
        try fixture.coordinator.cancellationStore.record(runID: old.id)
        let newerConversation = Conversation(id: "newer-review", provider: "codex", thread: fixture.conversation.thread)
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
            cancellationStore: cancellationStore
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
