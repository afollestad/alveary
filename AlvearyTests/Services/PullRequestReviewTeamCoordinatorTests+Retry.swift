import Foundation
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test
    func `a failed third cross-check requires a decision before majority staging`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        await fixture.worker.configure(failedVoters: ["peer-2"])
        try fixture.start()

        let run = try await fixture.terminalRun()

        #expect(run.phase == .awaitingDecision)
        #expect(run.pausedPhase == .crossChecking)
        #expect(run.voteReports.count == 2)
        #expect(run.failures["crossChecking:peer-2"] != nil)
        #expect(run.canRetryFailedReviewers)
        #expect(run.canContinueWithMajority)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
    }

    @Test
    func `failed inspection retry launches only missing inspectors`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        await fixture.worker.configure(failedInspectors: ["peer-1", "peer-2"])
        try fixture.start()
        let failed = try await fixture.terminalRun()
        #expect(failed.canRetryFailedReviewers)
        await fixture.worker.configure()

        fixture.coordinator.retryFailedReviewers(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)

        #expect(try await fixture.terminalRun().phase == .staged)
        #expect(await fixture.worker.calls.filter { $0.phase == "inspection" && $0.memberID == "lead" }.count == 1)
        #expect(await fixture.worker.calls.filter { $0.phase == "inspection" }.count == 5)
    }

    @Test
    func `retry failed cross-checks keeps canonical findings and completed reports`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let failed = try await failCrossChecks(fixture)
        await fixture.worker.configure()

        fixture.coordinator.retryFailedReviewers(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)
        let resumed = try await fixture.terminalRun()

        #expect(resumed.phase == .staged)
        #expect(resumed.generation == failed.generation + 1)
        #expect(resumed.inspections == failed.inspections)
        #expect(resumed.canonical == failed.canonical)
        #expect(resumed.voteReports["lead"] == failed.voteReports["lead"])
        #expect(resumed.failures == ["inspecting:peer-2": "Provider failed"])
        let calls = await fixture.worker.calls
        #expect(calls.filter { $0.phase == "inspection" }.count == 3)
        #expect(calls.filter { $0.phase == "consolidation" }.count == 1)
        #expect(calls.filter { $0.phase == "votes" && $0.memberID == "lead" }.count == 1)
        #expect(calls.filter { $0.phase == "votes" }.count == 5)
        #expect(await fixture.worker.cancelledRunIDs.isEmpty)
    }

    @Test
    func `settled active retry validates the card identity and uses the app action`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try await failCrossChecks(fixture)
        run.phase = .crossChecking
        try fixture.coordinator.persist(run)
        #expect(run.canRetryFailedReviewers)
        fixture.coordinator.retryFailedReviewers(conversationID: run.conversationID, runID: "old-run", generation: run.generation)
        fixture.coordinator.retryFailedReviewers(conversationID: run.conversationID, runID: run.id, generation: run.generation + 1)
        #expect(fixture.coordinator.runs[run.conversationID]?.generation == run.generation)
        await fixture.worker.configure()

        NotificationCenter.default.post(name: .reviewTeamRetryFailedRequested, object: nil, userInfo: [
            "conversationID": run.conversationID, "runID": run.id, "generation": run.generation
        ])

        #expect(try await fixture.terminalRun().phase == .staged)
        #expect(await fixture.worker.calls.filter { $0.phase == "inspection" }.count == 3)
        #expect(await fixture.worker.cancelledRunIDs.isEmpty)
    }

    @Test(arguments: [ReviewTeamRun.Phase.staged, .completed, .cancelled, .preparing, .staging])
    func `failed reviewers are not retryable outside unfinished review phases`(phase: ReviewTeamRun.Phase) async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try await failCrossChecks(fixture)
        run.phase = phase
        try fixture.coordinator.persist(run)

        fixture.coordinator.retryFailedReviewers(conversationID: run.conversationID, runID: run.id, generation: run.generation)

        #expect(!run.canRetryFailedReviewers)
        #expect(fixture.coordinator.runs[run.conversationID]?.generation == run.generation)
    }

    @Test
    func `retry requires every reviewer to settle and protects a terminal receipt`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try await failCrossChecks(fixture)
        run.phase = .crossChecking
        run.failures.removeValue(forKey: "crossChecking:peer-2")
        #expect(!run.canRetryFailedReviewers)
        run.failures["crossChecking:peer-2"] = "Failed"
        #expect(run.canRetryFailedReviewers)
        run.resultHash = "already-staged"
        #expect(!run.canRetryFailedReviewers)
        run.resultHash = nil
        run.requiresNewRun = true
        #expect(!run.canRetryFailedReviewers)
    }

    @Test
    func `changed packet blocks failed-worker retry without restarting completed workers`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let failed = try await failCrossChecks(fixture)
        fixture.service.reviewFeedbackResult = .success(Data("{\"feedback\":\"changed\"}".utf8))
        let previousCalls = await fixture.worker.calls.count

        fixture.coordinator.retryFailedReviewers(conversationID: failed.conversationID, runID: failed.id, generation: failed.generation)
        let resumed = try await fixture.terminalRun()

        #expect(resumed.phase == .failed)
        #expect(resumed.requiresNewRun == true)
        #expect(resumed.error == ReviewTeamError.retryInputChanged.localizedDescription)
        #expect(resumed.inspections == failed.inspections)
        #expect(await fixture.worker.calls.count == previousCalls)
    }

    @Test
    func `relaunch retains explicit voting retry without restarting inspection`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try await failCrossChecks(fixture)
        run.phase = .interrupted
        run.retryPhase = .crossChecking
        try fixture.coordinator.persist(run)
        await fixture.worker.configure()

        fixture.coordinator.recover()

        #expect(try await fixture.terminalRun().phase == .staged)
        #expect(await fixture.worker.calls.filter { $0.phase == "inspection" }.count == 3)
        #expect(await fixture.worker.calls.filter { $0.phase == "votes" }.count == 5)
    }

    private func failCrossChecks(_ fixture: ReviewCoordinatorFixture) async throws -> ReviewTeamRun {
        await fixture.worker.configure(failedInspectors: ["peer-2"], failedVoters: ["peer-1", "peer-2"])
        try fixture.start()
        let paused = try await fixture.terminalRun()
        #expect(paused.phase == .awaitingDecision)
        #expect(paused.pausedPhase == .inspecting)
        fixture.coordinator.continueWithMajority(conversationID: paused.conversationID, runID: paused.id, generation: paused.generation)
        let run = try await fixture.terminalRun()
        #expect(run.phase == .failed)
        #expect(run.canRetryFailedReviewers)
        return run
    }
}
