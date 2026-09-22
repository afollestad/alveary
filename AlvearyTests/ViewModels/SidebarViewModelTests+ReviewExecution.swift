import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testActiveCodeReviewRefusesArchiveAndDeleteWithoutTearingDownRuntime() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Reviewed", projectPath: "/tmp/active-code-review", conversationIDs: ["review-main"]
        )
        thread.isPinned = true
        try fixture.context.save()
        let activity = fixture.viewModel.threadLifecycle.reviewActivity
        beginLifecycleReview(activity, conversationID: "review-main")

        XCTAssertEqual(fixture.viewModel.threadCleanupBlockedReason(for: thread), activeReviewCleanupReason)
        await assertActiveReviewRefusal { try await fixture.viewModel.archiveThread(thread) }
        await assertActiveReviewRefusal { try await fixture.viewModel.deleteThread(thread) }

        let saved = try fixture.requireThread(thread)
        XCTAssertNil(saved.archivedAt)
        XCTAssertTrue(saved.isPinned)
        XCTAssertNotNil(fixture.context.resolveConversation(conversationID: "review-main"))
        let destroyed = await fixture.agentsManager.destroyCalls()
        XCTAssertTrue(destroyed.isEmpty)

        activity.end(lifecycleReviewIdentifier, kind: .review)
        XCTAssertNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
        try await fixture.viewModel.archiveThread(thread)
        XCTAssertNotNil(thread.archivedAt)
    }

    func testTeamReviewInASiblingConversationBlocksOnlyItsOwningThread() async throws {
        let fixture = try SidebarTestFixture()
        let owner = try fixture.insertThread(
            projectName: "Reviewed", projectPath: "/tmp/sibling-team-review", conversationIDs: ["quiet-main", "team-sibling"]
        )
        let unrelated = try fixture.insertThread(
            projectName: "Other", projectPath: "/tmp/unrelated-review-thread", conversationIDs: ["other-main"]
        )
        let activity = fixture.viewModel.threadLifecycle.reviewActivity
        activity.setCollectivePhase(.inspecting, identifier: lifecycleReviewIdentifier, conversationID: "team-sibling")

        await assertActiveReviewRefusal { try await fixture.viewModel.archiveThread(owner) }
        await assertActiveReviewRefusal { try await fixture.viewModel.deleteThread(owner) }
        activity.begin(lifecycleReviewIdentifier, kind: .addressFeedback)
        activity.attach(conversationID: "other-main", identifier: lifecycleReviewIdentifier, kind: .addressFeedback)
        try await fixture.viewModel.archiveThread(unrelated)

        XCTAssertNil(owner.archivedAt)
        XCTAssertNotNil(unrelated.archivedAt)
        let destroyed = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyed, ["other-main"])
    }

    func testSavedTeamReviewProtectsThreadBeforeCoordinatorRecovery() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Recovery", projectPath: "/tmp/saved-review-cleanup", conversationIDs: ["saved-review-main"]
        )
        let conversation = try XCTUnwrap(thread.conversations.first)
        var run = makeLifecycleReviewRun(conversationID: conversation.id)
        run.phase = .interrupted
        try conversation.storeCollectiveReviewRun(run)
        try fixture.context.save()

        XCTAssertEqual(fixture.viewModel.threadCleanupBlockedReason(for: thread), activeReviewCleanupReason)
        await assertActiveReviewRefusal { try await fixture.viewModel.deleteThread(thread) }

        run.phase = .cancelled
        try conversation.storeCollectiveReviewRun(run)
        try fixture.context.save()

        XCTAssertNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
        try await fixture.viewModel.deleteThread(thread)
        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testProjectDeletionRechecksReviewStartedAfterSnapshot() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Reviewed", projectPath: "/tmp/project-review-cleanup", conversationIDs: ["project-review-main"]
        )
        let project = try XCTUnwrap(thread.project)
        let projectID = project.persistentModelID
        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(project)
        let activity = fixture.viewModel.threadLifecycle.reviewActivity
        activity.setCollectivePhase(.inspecting, identifier: lifecycleReviewIdentifier, conversationID: "project-review-main")

        XCTAssertThrowsError(try fixture.viewModel.commitProjectDeletion(snapshot)) { error in
            XCTAssertEqual(error.localizedDescription, activeReviewCleanupReason)
        }
        await assertActiveReviewRefusal { try await fixture.viewModel.deleteProject(project) }

        XCTAssertNotNil(fixture.context.resolveProject(id: projectID))
        XCTAssertTrue(try fixture.threadExists(thread))
        let destroyed = await fixture.agentsManager.destroyCalls()
        XCTAssertTrue(destroyed.isEmpty)
    }

    func testArchiveRechecksTeamReviewAfterExactScheduledCallbackQuiesces() async throws {
        var activity: PullRequestAgenticThreadActivity?
        var quiescenceCount = 0
        let fixture = try SidebarTestFixture(stopAndWaitForScheduledTaskRun: { _ in
            quiescenceCount += 1
            if quiescenceCount == 2 {
                activity?.setCollectivePhase(.inspecting, identifier: lifecycleReviewIdentifier, conversationID: "callback-review-race")
            }
        })
        activity = fixture.viewModel.threadLifecycle.reviewActivity
        let (thread, run) = try insertScheduledTaskThread(fixture: fixture, status: .success, conversationID: "callback-review-race")
        run.thread = nil
        thread.scheduledTaskRun = nil
        run.targetThread = thread
        run.targetConversationIDSnapshot = "callback-review-race"
        run.isExactTargetSnapshot = true
        thread.targetedScheduledTaskRuns = [run]
        try fixture.context.save()

        await assertActiveReviewRefusal { try await fixture.viewModel.archiveThread(thread) }

        XCTAssertGreaterThanOrEqual(quiescenceCount, 2)
        XCTAssertNil(thread.archivedAt)
        let destroyed = await fixture.agentsManager.destroyCalls()
        XCTAssertTrue(destroyed.isEmpty)
    }

    func testDeleteRechecksReviewStartedWhileScheduledRunQuiesces() async throws {
        let gate = SidebarScheduledRunQuiescenceGate()
        let fixture = try SidebarTestFixture(stopAndWaitForScheduledTaskRun: { await gate.stopAndWait(runID: $0) })
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture, status: .preparing, conversationID: "delete-review-race"
        )
        let threadID = thread.persistentModelID
        let deletion = Task { @MainActor in try await fixture.viewModel.deleteThread(thread) }
        await gate.waitUntilEntered()
        beginLifecycleReview(fixture.viewModel.threadLifecycle.reviewActivity, conversationID: "delete-review-race")
        run.status = .interrupted
        try fixture.context.save()
        gate.release()

        await assertActiveReviewRefusal { try await deletion.value }

        XCTAssertNotNil(fixture.context.resolveThread(id: threadID))
        XCTAssertNotNil(fixture.context.resolveConversation(conversationID: "delete-review-race"))
        let destroyed = await fixture.agentsManager.destroyCalls()
        XCTAssertTrue(destroyed.isEmpty)
    }
}

private let lifecycleReviewIdentifier = PullRequestIdentifier(owner: "octo", repo: "alveary", number: 7)
private let activeReviewCleanupReason =
    "This thread has an active code review. Wait for it to finish or cancel it before archiving or deleting this thread."

@MainActor
private func beginLifecycleReview(_ activity: PullRequestAgenticThreadActivity, conversationID: String) {
    activity.begin(lifecycleReviewIdentifier, kind: .review)
    activity.attach(conversationID: conversationID, identifier: lifecycleReviewIdentifier, kind: .review)
}

@MainActor
private func assertActiveReviewRefusal(
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        XCTFail("Expected active review to block cleanup", file: file, line: line)
    } catch {
        guard case .activeReview = error as? SidebarViewModelError else {
            return XCTFail("Expected activeReview, got \(error)", file: file, line: line)
        }
    }
}

private func makeLifecycleReviewRun(conversationID: String) -> ReviewTeamRun {
    ReviewTeamRun(
        payloadVersion: 1, id: "saved-review", proposalID: "saved-proposal", conversationID: conversationID,
        identifier: lifecycleReviewIdentifier, url: URL(string: "https://github.com/octo/alveary/pull/7")!,
        team: reviewTestTeam(), criteria: "Find bugs.",
        priorProposal: PullRequestCollectiveReviewStagingSnapshot(
            proposalOwnerConversationID: nil, proposalID: nil, proposalContentHash: nil, editState: nil
        ),
        createdAt: Date(timeIntervalSince1970: 1_000), generation: 0, phase: .preparing,
        inspections: [:], voteReports: [:], accepted: [], attempts: [:], failures: [:], supersededProposalIDs: []
    )
}
