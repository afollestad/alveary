import Foundation
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test func `empty majority pauses before approval and explicit continue does not rerun inspection`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let paused = try await pauseInspection(fixture, empty: true)
        #expect(paused.inspections.count == 2)
        #expect(paused.requiredVotes == 2)
        #expect(paused.canonical == nil)
        #expect(paused.voteReports.isEmpty)
        #expect(paused.canContinueWithMajority)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(fixture.coordinator.activity.isWorking(fixture.identifier, kind: .review))

        NotificationCenter.default.post(name: .reviewTeamContinueRequested, object: nil, userInfo: [
            "conversationID": paused.conversationID, "runID": paused.id, "generation": paused.generation
        ])

        let continued = try await fixture.terminalRun()
        #expect(continued.phase == .staged)
        #expect(continued.continuedPhases == [.inspecting])
        #expect(continued.inspections == paused.inspections)
        #expect(continued.requiredVotes == 2)
        #expect(await fixture.worker.calls.count == 3)
        #expect(try fixture.conversation.pullRequestReviewProposal()?.event == "approve")
        #expect(fixture.service.submittedReviews.isEmpty)
    }

    @Test func `retrying a paused inspection runs only the missing reviewer`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let paused = try await pauseInspection(fixture, empty: true)
        await fixture.worker.configure(empty: true)

        fixture.coordinator.retryFailedReviewers(conversationID: paused.conversationID, runID: paused.id, generation: paused.generation)

        let resumed = try await fixture.terminalRun()
        #expect(resumed.phase == .staged)
        #expect(resumed.inspections.count == 3)
        #expect(resumed.continuedPhases?.isEmpty != false)
        #expect(resumed.pausedPhase == nil)
        #expect(resumed.failures.isEmpty)
        let calls = await fixture.worker.calls
        #expect(calls.count == 4)
        #expect(calls.filter { $0.memberID == "lead" }.count == 1)
        #expect(calls.filter { $0.memberID == "peer-2" }.count == 2)
    }

    @Test func `partial inspection and cross-check each require their own decision`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        await fixture.worker.configure(failedInspectors: ["peer-2"], failedVoters: ["peer-2"])
        try fixture.start()
        let inspection = try await fixture.terminalRun()
        #expect(inspection.pausedPhase == .inspecting)
        fixture.coordinator.continueWithMajority(conversationID: inspection.conversationID, runID: inspection.id,
                                                 generation: inspection.generation)

        let voting = try await fixture.terminalRun()
        #expect(voting.phase == .awaitingDecision)
        #expect(voting.pausedPhase == .crossChecking)
        #expect(voting.continuedPhases == [.inspecting])
        #expect(voting.voteReports.count == 2)
        #expect(voting.canContinueWithMajority)
        #expect(voting.accepted.isEmpty)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        let previousCalls = await fixture.worker.calls.count

        fixture.coordinator.continueWithMajority(conversationID: voting.conversationID, runID: voting.id, generation: voting.generation)

        let completed = try await fixture.terminalRun()
        #expect(completed.phase == .staged)
        #expect(completed.continuedPhases == [.inspecting, .crossChecking])
        #expect(completed.inspections == voting.inspections)
        #expect(completed.voteReports == voting.voteReports)
        #expect(completed.accepted.first?.priority == 2)
        #expect(completed.requiredVotes == 2)
        #expect(await fixture.worker.calls.count == previousCalls)
    }

    @Test func `recovery leaves a partial decision paused and reserves the PR until cancellation`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let paused = try await pauseInspection(fixture, empty: true)

        fixture.coordinator.recover()

        #expect(fixture.coordinator.runs[paused.conversationID]?.phase == .awaitingDecision)
        #expect(fixture.coordinator.runs[paused.conversationID]?.generation == paused.generation)
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(fixture.coordinator.activity.isWorking(fixture.identifier, kind: .review))
        #expect(try fixture.coordinator.hasUnfinishedReview(for: fixture.identifier))
        #expect(throws: ReviewTeamError.self) { try fixture.start() }
        #expect(await fixture.worker.calls.count == 3)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)

        fixture.coordinator.cancel(conversationID: paused.conversationID)

        #expect(fixture.coordinator.runs[paused.conversationID]?.phase == .cancelled)
        #expect(!fixture.coordinator.activity.isWorking(fixture.identifier, kind: .review))
        #expect(try !fixture.coordinator.hasUnfinishedReview(for: fixture.identifier))
    }

    @Test func `stale decision controls and missing quorum cannot authorize a partial review`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        let paused = try await pauseInspection(fixture, empty: true)
        fixture.coordinator.continueWithMajority(conversationID: paused.conversationID, runID: "stale-run", generation: paused.generation)
        fixture.coordinator.continueWithMajority(conversationID: paused.conversationID, runID: paused.id, generation: paused.generation + 1)
        for (runID, generation) in [("stale-run", paused.generation), (paused.id, paused.generation + 1)] {
            NotificationCenter.default.post(name: .reviewTeamCancelRequested, object: nil, userInfo: [
                "conversationID": paused.conversationID, "runID": runID, "generation": generation
            ])
        }
        #expect(fixture.coordinator.runs[paused.conversationID]?.generation == paused.generation)
        #expect(fixture.coordinator.runs[paused.conversationID]?.phase == .awaitingDecision)

        var belowQuorum = paused
        belowQuorum.inspections.removeValue(forKey: "lead")
        belowQuorum.failures["inspecting:lead"] = "Failed"
        try fixture.coordinator.persist(belowQuorum)
        #expect(!belowQuorum.canContinueWithMajority)
        fixture.coordinator.continueWithMajority(conversationID: paused.conversationID, runID: paused.id, generation: paused.generation)

        #expect(fixture.coordinator.runs[paused.conversationID]?.generation == paused.generation)
        #expect(await fixture.worker.calls.count == 3)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
    }

    @Test(arguments: [false, true])
    func `recovering a terminal run cannot clear another paused run reservation`(terminalInsertedFirst: Bool) async throws {
        let fixture = try ReviewCoordinatorFixture()
        let other = Conversation(id: "other-review", provider: "codex", thread: fixture.conversation.thread)
        fixture.container.mainContext.insert(other)
        let terminalConversation = terminalInsertedFirst ? fixture.conversation : other
        let pausedConversation = terminalInsertedFirst ? other : fixture.conversation
        var terminal = try fixture.makeRun(conversationID: terminalConversation.id)
        terminal.phase = .staged
        terminal.resultHash = "old-terminal-receipt"
        var paused = try fixture.makeRun(conversationID: pausedConversation.id)
        paused.phase = .awaitingDecision
        paused.pausedPhase = .inspecting
        paused.inspections = ["lead": ReviewInspectionReport(findings: []), "peer-1": ReviewInspectionReport(findings: [])]
        paused.failures = ["inspecting:peer-2": "Timed out"]
        try terminalConversation.storeCollectiveReviewRun(terminal)
        try pausedConversation.storeCollectiveReviewRun(paused)
        try fixture.container.mainContext.save()
        #expect(fixture.coordinator.runs.isEmpty)

        fixture.coordinator.recover()

        #expect(fixture.coordinator.activity.isWorking(fixture.identifier, kind: .review))
        #expect(fixture.coordinator.runs[paused.conversationID]?.phase == .awaitingDecision)
        #expect(fixture.coordinator.workingConversationIDs.isEmpty)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func `continue rejects changed feedback or revisions before launching more workers`(changeRevision: Bool) async throws {
        let fixture = try ReviewCoordinatorFixture()
        let paused = try await pauseInspection(fixture, empty: true)
        if changeRevision {
            var detail = try fixture.service.detailResult.get()
            detail.headRefOid = "changed-head"
            fixture.service.detailResult = .success(detail)
        } else {
            fixture.service.reviewFeedbackResult = .success(Data("{\"feedback\":\"changed\"}".utf8))
        }

        fixture.coordinator.continueWithMajority(conversationID: paused.conversationID, runID: paused.id, generation: paused.generation)

        let failed = try await fixture.terminalRun()
        #expect(failed.phase == .failed)
        #expect(failed.requiresNewRun == true)
        #expect(failed.error == (changeRevision ? ReviewTeamError.revisionChanged : .retryInputChanged).localizedDescription)
        #expect(failed.inspections == paused.inspections)
        #expect(await fixture.worker.calls.count == 3)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
    }

    private func pauseInspection(_ fixture: ReviewCoordinatorFixture, empty: Bool) async throws -> ReviewTeamRun {
        await fixture.worker.configure(empty: empty, failedInspectors: ["peer-2"])
        try fixture.start()
        let run = try await fixture.terminalRun()
        #expect(run.phase == .awaitingDecision)
        #expect(run.pausedPhase == .inspecting)
        return run
    }
}
