import Foundation
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test
    func `manual failed reviewer retry renews quota budget and keeps saved wait visible`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try ReviewCoordinatorFixture(historyStore: ReviewTeamHistoryStore(rootDirectory: root))
        let detail = try fixture.service.detailResult.get()
        let context = PullRequestReviewContext(detail: detail)
        fixture.service.reviewContextResult = .success(context)
        fixture.service.revisionResult = .success(context.revision)
        await fixture.worker.configure(failedVoters: ["peer-2"])
        try fixture.start()
        let paused = try await fixture.terminalRun()
        #expect(paused.phase == .awaitingDecision)
        #expect(paused.pausedPhase == .crossChecking)
        #expect(paused.canContinueWithMajority)
        fixture.service.detailResult = .failure(.rateLimited)
        fixture.coordinator.continueWithMajority(
            conversationID: paused.conversationID, runID: paused.id, generation: paused.generation
        )
        let failed = try await fixture.terminalRun()
        #expect(failed.phase == .failed)
        #expect(failed.gitHubRateLimitFailures == 5)
        #expect(failed.canRetryFailedReviewers)
        #expect(failed.voteReports.count == 2)
        #expect(failed.failures["crossChecking:peer-2"] != nil)
        let previousContextReads = fixture.service.reviewContextCallCount
        fixture.service.reviewContextResult = .failure(.rateLimited)
        fixture.coordinator.retryFailedReviewers(
            conversationID: failed.conversationID, runID: failed.id, generation: failed.generation
        )
        let retrying = try #require(fixture.coordinator.runs[failed.conversationID])
        #expect(retrying.phase == .waitingForGitHub)
        #expect(retrying.gitHubRateLimitFailures == nil)
        let retried = try await fixture.terminalRun()
        #expect(retried.phase == .failed)
        #expect(fixture.service.reviewContextCallCount - previousContextReads == 5)
        #expect(retried.gitHubRateLimitFailures == 5)
    }

    @Test
    func `late quota failures retry only the failed read`() async throws {
        let gate = MockShellRunnerGate()
        let fixture = try ReviewCoordinatorFixture(waitForGitHub: { _ in await gate.wait() })
        defer { gate.open() }
        let revision = PullRequestReviewContext(detail: try fixture.service.detailResult.get()).revision
        fixture.service.revisionResults = [.success(revision), .failure(.rateLimited), .success(revision)]
        try fixture.start()
        try await fixture.wait { fixture.coordinator.runs[fixture.conversation.id]?.phase == .waitingForGitHub }
        gate.open()
        #expect(try await fixture.terminalRun().phase == .staged)
        #expect(fixture.service.detailCallCount == 1)
        #expect(fixture.service.reviewContextCallCount == 1)
        #expect(fixture.service.revisionCallCount == 3)
    }

    @Test(arguments: [false, true])
    func `feedback quota recovery validates revision before paid work`(changedHead: Bool) async throws {
        let gate = MockShellRunnerGate()
        let fixture = try ReviewCoordinatorFixture(waitForGitHub: { _ in await gate.wait() })
        defer { gate.open() }
        fixture.service.reviewFeedbackResult = .failure(.rateLimited)
        try fixture.start()
        try await fixture.wait { fixture.coordinator.runs[fixture.conversation.id]?.phase == .waitingForGitHub }
        if changedHead {
            var detail = try fixture.service.detailResult.get()
            detail.headRefOid = "changed-head"
            fixture.service.detailResult = .success(detail)
        }
        fixture.service.reviewFeedbackResult = .success(Data("{}".utf8))
        gate.open()
        let result = try await fixture.terminalRun()
        #expect(result.phase == (changedHead ? .failed : .staged))
        #expect(fixture.service.reviewContextCallCount == 1)
        #expect(fixture.service.feedbackCallCount == 2)
        #expect(fixture.service.revisionCallCount == (changedHead ? 1 : 3))
        #expect(fixture.service.detailCallCount == (changedHead ? 0 : 1))
        #expect(await fixture.worker.calls.count == (changedHead ? 0 : 7))
        if changedHead {
            #expect(result.requiresNewRun == true)
            #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        }
    }

    @Test(arguments: [2, 5])
    func `team size does not multiply GitHub acquisition`(count: Int) async throws {
        let fixture = try ReviewCoordinatorFixture()
        try fixture.start(team: reviewTestTeam(count: count))
        let run = try await fixture.terminalRun()
        #expect(run.phase == .staged)
        #expect(fixture.service.reviewContextCallCount == 1)
        #expect(fixture.service.revisionCallCount == 2)
        #expect(fixture.service.detailCallCount == 1)
        #expect(fixture.service.feedbackCallCount == 1)
    }

    @Test(arguments: [ReviewTeamRun.Phase.preparing, .consolidating, .staging])
    func `quota recovery retains completed reviewer work`(phase: ReviewTeamRun.Phase) async throws {
        let gate = MockShellRunnerGate()
        let fixture = try ReviewCoordinatorFixture(waitForGitHub: { _ in await gate.wait() })
        defer { gate.open() }
        let detail = try fixture.service.detailResult.get()
        let context = PullRequestReviewContext(detail: detail)
        fixture.service.reviewContextResult = .success(context)
        fixture.service.revisionResult = .success(context.revision)
        let limit = PullRequestsServiceError.rateLimit(GitHubRateLimit(
            resource: "graphql", isSecondary: false, retryAt: Date().addingTimeInterval(60)
        ))
        switch phase {
        case .preparing: fixture.service.reviewContextResult = .failure(limit)
        case .consolidating: fixture.service.revisionResult = .failure(limit)
        default: fixture.service.detailResult = .failure(limit)
        }
        try fixture.start()
        try await fixture.wait { fixture.coordinator.runs[fixture.conversation.id]?.phase == .waitingForGitHub }
        let paused = try #require(fixture.coordinator.runs[fixture.conversation.id])
        #expect(paused.gitHubWait?.resumePhase == phase)
        #expect(paused.inspections.count == (phase == .preparing ? 0 : 3))
        fixture.service.reviewContextResult = .success(context)
        fixture.service.revisionResult = .success(context.revision)
        fixture.service.detailResult = .success(detail)
        gate.open()
        let finished = try await fixture.terminalRun()
        #expect(finished.phase == .staged)
        #expect(await fixture.worker.inspectionCount == 3)
        #expect(await fixture.worker.calls.count == 7)
        #expect(fixture.service.feedbackCallCount == 1)
        #expect(try fixture.conversation.pullRequestReviewProposal() != nil)
    }

    @Test
    func `five quota responses stop automatic attempts and allow manual retry`() async throws {
        let fixture = try ReviewCoordinatorFixture()
        fixture.service.reviewContextResult = .failure(.rateLimited)
        try fixture.start()
        let failed = try await fixture.terminalRun()
        #expect(failed.phase == .failed)
        #expect(failed.gitHubRateLimitFailures == 5)
        #expect(fixture.service.reviewContextCallCount == 5)
        #expect(await fixture.worker.calls.isEmpty)
        fixture.service.reviewContextResult = nil
        fixture.coordinator.retry(conversationID: fixture.conversation.id)
        #expect(try await fixture.terminalRun().phase == .staged)
    }

    @Test
    func `cancelling a quota wait never resumes reviewers`() async throws {
        let gate = MockShellRunnerGate()
        let fixture = try ReviewCoordinatorFixture(waitForGitHub: { _ in await gate.wait() })
        defer { gate.open() }
        fixture.service.reviewContextResult = .failure(.rateLimited)
        try fixture.start()
        let task = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.wait { fixture.coordinator.runs[fixture.conversation.id]?.phase == .waitingForGitHub }
        fixture.coordinator.cancel(conversationID: fixture.conversation.id)
        gate.open()
        await task.value
        #expect(try fixture.conversation.collectiveReviewRun()?.phase == .cancelled)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func `quota recovery after relaunch restores frozen history or requires attention`(removeHistory: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReviewTeamHistoryStore(rootDirectory: root)
        let gate = MockShellRunnerGate()
        let fixture = try ReviewCoordinatorFixture(historyStore: store, waitForGitHub: { _ in await gate.wait() })
        defer { gate.open() }
        fixture.service.revisionResult = .failure(.rateLimited)
        try fixture.start()
        let originalTask = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.wait { fixture.coordinator.runs[fixture.conversation.id]?.phase == .waitingForGitHub }
        fixture.coordinator.prepareForTermination()
        fixture.service.revisionResult = nil
        fixture.service.reviewFeedbackResult = .success(Data("changed feedback".utf8))
        if removeHistory { try FileManager.default.removeItem(at: root) }
        fixture.coordinator.recover()
        gate.open()
        await originalTask.value
        let result = try await fixture.terminalRun()
        #expect(result.phase == (removeHistory ? .failed : .staged))
        #expect(await fixture.worker.inspectionCount == 3)
        #expect(fixture.service.feedbackCallCount == 1)
    }

    @Test
    func `a changed revision during cooldown cannot stage stale findings`() async throws {
        let gate = MockShellRunnerGate()
        let fixture = try ReviewCoordinatorFixture(waitForGitHub: { _ in await gate.wait() })
        defer { gate.open() }
        fixture.service.revisionResult = .failure(.rateLimited)
        try fixture.start()
        try await fixture.wait { fixture.coordinator.runs[fixture.conversation.id]?.phase == .waitingForGitHub }
        fixture.service.revisionResult = .success(PullRequestRevision(status: .open, baseRefOid: "base", headRefOid: "changed"))
        gate.open()
        let result = try await fixture.terminalRun()
        #expect(result.phase == .failed)
        #expect(result.requiresNewRun == true)
        #expect(try fixture.conversation.pullRequestReviewProposal() == nil)
        #expect(await fixture.worker.inspectionCount == 3)
    }
}
