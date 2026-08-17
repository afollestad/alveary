import Foundation
import XCTest

@testable import Alveary

/// The card paints its comments from cached hunks and refreshes behind that paint, so reopening a
/// thread never shows a loading caption for a review Alveary already has the diff for.
extension ReviewProposalCoordinatorTests {
    func testACachedPreviewPaintsBeforeAnyNetworkCall() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        // Held closed for the whole test: a cached paint must not wait on it.
        fixture.service.detailGate = PullRequestsServiceGate()

        try await fixture.waitForCachedPaint()

        guard case .loaded(let preview)? = fixture.coordinator.preview(
            forProposalID: ReviewProposalFixture.proposalID
        ) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.files.map(\.path), ["File0.swift"])
        XCTAssertEqual(preview.proposedCommentCount, 1)
        let thread = try XCTUnwrap(preview.annotations.threads.values.first)
        XCTAssertEqual(thread.comments.first?.author, "octocat")
        XCTAssertEqual(thread.comments.first?.isProposed, true)
        XCTAssertEqual(fixture.service.detailCallCount, 0)
    }

    func testTheRefreshStillRunsBehindACachedPaint() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier)
        detail.viewerLogin = "octocat"
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))
        try await fixture.waitForCachedPaint()

        // Not the cache file: the fixture seeded it, so it is already non-empty.
        let recorder = fixture.cardStateRecorder()
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.wait(for: recorder)

        XCTAssertEqual(fixture.service.detailCallCount, 1)
        XCTAssertEqual(fixture.service.diffCallCount, 1)
        guard case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
    }

    /// A second render must not open a second round trip, which is what separates the refresh
    /// marker from `previews` being non-nil.
    func testASecondRenderDoesNotRefreshAgain() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)

        XCTAssertEqual(fixture.service.detailCallCount, 1)
    }

    /// The hunks on screen are still what confirming would publish, so a failed refresh must not
    /// replace them with an error.
    func testARefreshFailureKeepsTheCachedPreview() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        try await fixture.waitForCachedPaint()
        fixture.service.detailResult = .failure(.rateLimited)

        let recorder = fixture.cardStateRecorder()
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.wait(for: recorder)

        XCTAssertEqual(fixture.service.detailCallCount, 1)
        guard case .loaded(let preview)? = fixture.coordinator.preview(
            forProposalID: ReviewProposalFixture.proposalID
        ) else {
            return XCTFail("expected the cached preview to survive the failure")
        }
        XCTAssertEqual(preview.files.map(\.path), ["File0.swift"])
    }

    func testASuccessfulRefreshWritesTheCache() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(comments: comments)
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForCachedEntry()

        let entry = try XCTUnwrap(fixture.cachedEntries()[ReviewProposalFixture.proposalID])
        XCTAssertEqual(entry.identifier, ReviewProposalFixture.identifier)
        XCTAssertEqual(entry.files.map(\.path), ["File0.swift"])
    }

    func testAddingAStagedCommentLetsTheDiffReloadAgain() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        XCTAssertTrue(
            fixture.coordinator.addStagedComment(
                proposalID: ReviewProposalFixture.proposalID,
                path: "File1.swift",
                line: 1,
                side: .right,
                body: "And this."
            )
        )
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        XCTAssertEqual(fixture.service.detailCallCount, 2)
    }

    /// Propose time seeds the cache after the coordinator exists, then posts the lifecycle
    /// notification — the reload it triggers must re-read the file, or the proposing session's own
    /// card never finds its seed and loads over the network.
    func testASeedWrittenAfterInitPaintsOnTheNextReload() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(comments: comments)
        // Held closed for the whole test: the paint must come from the file, not the network.
        fixture.service.detailGate = PullRequestsServiceGate()
        let cache = PullRequestReviewProposalPreviewCache(fileURL: fixture.previewCacheURL)
        await cache.save(
            ReviewProposalFixture.seededEntry(for: comments),
            forProposalID: ReviewProposalFixture.proposalID
        )

        fixture.notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: nil)
        try await fixture.waitForCachedPaint()

        guard case .loaded(let preview)? = fixture.coordinator.preview(
            forProposalID: ReviewProposalFixture.proposalID
        ) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.files.map(\.path), ["File0.swift"])
        XCTAssertEqual(fixture.service.detailCallCount, 0)
    }

    /// A cache written for a proposal that was superseded by one against another pull request must
    /// not paint — those hunks belong to different code.
    func testAnEntryForAnotherPullRequestIsNotPainted() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(
                for: comments,
                identifier: PullRequestIdentifier(owner: "octo", repo: "beta", number: 99)
            )
        )
        fixture.service.detailGate = PullRequestsServiceGate()

        let recorder = fixture.cardStateRecorder()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID))
        XCTAssertEqual(recorder.count, 0)
    }

    func testACorruptCacheFileReadsAsCold() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")],
            corruptCache: true
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        XCTAssertNil(fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        guard case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            XCTFail("expected the refresh to recover from a cold cache")
            return
        }
    }

    func testRejectingAProposalPrunesItsCachedHunks() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        try await fixture.waitForCachedPaint()

        XCTAssertTrue(fixture.coordinator.reject(proposalID: ReviewProposalFixture.proposalID))

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !fixture.cachedEntries().isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(fixture.cachedEntries().isEmpty)
    }

    /// A pull request that moved on GitHub invalidates the hunks the card drew, which matters now
    /// that a preview outlives the launch that loaded it.
    func testARemoteChangeInvalidatesThePaintedPreview() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        try await fixture.waitForCachedPaint()

        fixture.notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: nil,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: ReviewProposalFixture.identifier,
                    affectsListRow: false
                )
            ]
        )

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) != nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertNil(fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID))
    }

    /// An announcement for a different pull request leaves this card alone.
    func testARemoteChangeForAnotherPullRequestLeavesThePreviewAlone() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        try await fixture.waitForCachedPaint()

        fixture.notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: nil,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: PullRequestIdentifier(owner: "octo", repo: "beta", number: 99),
                    affectsListRow: false
                )
            ]
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected the preview to survive an unrelated announcement")
        }
    }
}
