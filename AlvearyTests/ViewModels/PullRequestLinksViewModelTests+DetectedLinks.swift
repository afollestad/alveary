import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension PullRequestLinksViewModelTests {
    func testDetectedLinkPersistsASnapshotAndClearsItsPrompt() async throws {
        let harness = try Harness()
        let identifier = detectedIdentifier
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .open)
        )
        harness.thread.pendingPullRequestLinkPrompts = [makePrompt(identifier: identifier)]

        try await harness.viewModel.linkDetectedPullRequest(identifier, threadID: harness.thread.persistentModelID)

        XCTAssertEqual(harness.thread.linkedPullRequests.map(\.id), [identifier])
        XCTAssertEqual(harness.thread.linkedPullRequests.first?.summary.title, "Add caching")
        XCTAssertEqual(harness.thread.pendingPullRequestLinkPrompts, [])
    }

    /// A background link must not disable the popover's Link button or push an
    /// error into a field the user is not looking at.
    func testDetectedLinkLeavesPopoverStateAlone() async throws {
        let harness = try Harness()
        let identifier = detectedIdentifier
        harness.service.detailResult = .failure(.ghNotInstalled)
        harness.thread.pendingPullRequestLinkPrompts = [makePrompt(identifier: identifier)]

        do {
            try await harness.viewModel.linkDetectedPullRequest(identifier, threadID: harness.thread.persistentModelID)
            XCTFail("Expected the fetch failure to propagate")
        } catch let error as PullRequestsServiceError {
            XCTAssertEqual(error, .ghNotInstalled)
        }

        XCTAssertEqual(harness.thread.linkedPullRequests, [])
        XCTAssertNil(harness.viewModel.linkErrorMessage)
        XCTAssertFalse(harness.viewModel.isLinking)
        XCTAssertFalse(harness.viewModel.linkFailureNeedsGitSettings)
    }

    /// The prompt survives a failed link so the user can answer Yes again.
    func testFailedDetectedLinkKeepsThePromptAnswerable() async throws {
        let harness = try Harness()
        let identifier = detectedIdentifier
        harness.service.detailResult = .failure(.notAuthenticated)
        harness.thread.pendingPullRequestLinkPrompts = [makePrompt(identifier: identifier)]

        _ = try? await harness.viewModel.linkDetectedPullRequest(
            identifier,
            threadID: harness.thread.persistentModelID
        )

        XCTAssertEqual(harness.thread.pendingPullRequestLinkPrompts.count, 1)
    }

    func testAlreadyLinkedPullRequestSkipsTheFetchAndClearsItsPrompt() async throws {
        let harness = try Harness()
        let identifier = detectedIdentifier
        harness.thread.linkedPullRequests = [
            LinkedPullRequest(
                summary: makePullRequestSummary(number: identifier.number),
                linkedAt: Date(timeIntervalSince1970: 1)
            )
        ]
        harness.thread.pendingPullRequestLinkPrompts = [makePrompt(identifier: identifier)]

        try await harness.viewModel.linkDetectedPullRequest(identifier, threadID: harness.thread.persistentModelID)

        XCTAssertEqual(harness.service.detailCallCount, 0)
        XCTAssertEqual(harness.thread.linkedPullRequests.count, 1)
        XCTAssertEqual(harness.thread.pendingPullRequestLinkPrompts, [])
    }

    /// Detection can fire twice for the same pull request (a repeated prompt tap, or
    /// the same URL in two messages); the second must not start its own fetch.
    func testConcurrentDetectedLinksForTheSamePullRequestFetchOnce() async throws {
        let harness = try Harness()
        let identifier = detectedIdentifier
        let gate = PullRequestsServiceGate()
        harness.service.detailGate = gate
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .open)
        )

        let first = Task {
            try await harness.viewModel.linkDetectedPullRequest(
                identifier,
                threadID: harness.thread.persistentModelID
            )
        }
        try await waitUntil("expected the first fetch to be in flight") {
            harness.service.detailCallCount == 1
        }
        try await harness.viewModel.linkDetectedPullRequest(identifier, threadID: harness.thread.persistentModelID)
        gate.open()
        try await first.value

        XCTAssertEqual(harness.service.detailCallCount, 1)
        XCTAssertEqual(harness.thread.linkedPullRequests.count, 1)
    }

    func testDetectedLinkForAVanishedThreadIsANoOp() async throws {
        let harness = try Harness()
        let identifier = detectedIdentifier
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .open)
        )
        let threadID = harness.thread.persistentModelID
        harness.context.delete(harness.thread)
        try harness.context.save()

        try await harness.viewModel.linkDetectedPullRequest(identifier, threadID: threadID)

        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<AgentThread>()).count, 0)
    }

    private var detectedIdentifier: PullRequestIdentifier {
        PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    }

    private func makePrompt(identifier: PullRequestIdentifier) -> PendingPullRequestPrompt {
        PendingPullRequestPrompt(
            identifier: identifier,
            messageEventID: "message-1",
            conversationID: "conversation-1",
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
