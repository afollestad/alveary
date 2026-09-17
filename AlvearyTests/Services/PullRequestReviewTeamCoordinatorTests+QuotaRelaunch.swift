import Foundation
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test
    func `relaunch restores every cooldown before resuming saved waits`() async throws {
        let waits = RestoredReviewWaits()
        let restorationGate = PullRequestsServiceGate()
        let fixture = try ReviewCoordinatorFixture(waitForGitHub: { date in await waits.wait(until: date) })
        fixture.service.restoreRateLimitsGate = restorationGate
        defer { restorationGate.open(); waits.gate.open() }
        let context = fixture.container.mainContext
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        var savedRuns: [ReviewTeamRun] = []
        for number in 1...6 {
            let thread = AgentThread(name: "Saved review \(number)")
            let conversation = Conversation(id: UUID().uuidString, harness: "codex", thread: thread)
            context.insert(thread)
            context.insert(conversation)
            var run = try fixture.makeRun(
                conversationID: conversation.id, identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: number)
            )
            run.phase = number.isMultiple(of: 2) ? .interrupted : .waitingForGitHub
            run.gitHubWait = ReviewTeamGitHubWait(
                resumePhase: .preparing,
                limit: GitHubRateLimit(resource: "graphql", isSecondary: number == 6, retryAt: deadline)
            )
            try conversation.storeCollectiveReviewRun(run)
            savedRuns.append(run)
        }
        try context.save()
        fixture.coordinator.recover()
        let tasks = savedRuns.compactMap { fixture.coordinator.scheduledTaskForTesting(conversationID: $0.conversationID) }
        #expect(tasks.count == 6)
        try await fixture.wait { fixture.service.restoredRateLimits.count == 6 }
        #expect(waits.dates.isEmpty)
        #expect(fixture.service.restoredRateLimits.filter(\.isSecondary).count == 1)
        for saved in savedRuns {
            let run = try #require(fixture.coordinator.runs[saved.conversationID])
            #expect(run.phase == .waitingForGitHub)
            #expect(ReviewTeamRunCardPresentation.pauseExplanation(run) == saved.gitHubWait?.limit.waitingMessage)
        }
        restorationGate.open()
        try await fixture.wait { waits.dates.count == 6 }
        #expect(waits.dates.allSatisfy { $0 == deadline })
        #expect(fixture.service.reviewContextCallCount == 0)
        for saved in savedRuns { fixture.coordinator.cancel(conversationID: saved.conversationID) }
        waits.gate.open()
        for task in tasks { await task.value }
        #expect(fixture.service.reviewContextCallCount == 0)
        #expect(await fixture.worker.calls.isEmpty)
        #expect(savedRuns.allSatisfy { fixture.coordinator.runs[$0.conversationID]?.phase == .cancelled })
    }
}

@MainActor
private final class RestoredReviewWaits {
    let gate = MockShellRunnerGate()
    private(set) var dates: [Date] = []

    func wait(until date: Date) async {
        dates.append(date)
        await gate.wait()
    }
}
