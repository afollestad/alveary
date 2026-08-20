import Foundation
import XCTest

@testable import Alveary

/// The card paints its comments from cached hunks and refreshes behind that paint, so reopening a
/// thread never shows a loading caption for a review Alveary already has the diff for — and the
/// refresh itself starts at launch rather than waiting for that thread to be opened.
extension ReviewProposalCoordinatorTests {
    func testACachedPreviewPaintsWithoutWaitingForTheNetwork() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        // Held closed for the whole test: a cached paint must not wait on it. The warm refresh
        // chained behind the paint opens the call and blocks here, which is why the assertion
        // below is on the diff — no round trip can have completed to produce these hunks.
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
        XCTAssertEqual(fixture.service.diffCallCount, 0)
    }

    /// The refresh runs with no render to trigger it, so opening the thread costs no round trip.
    func testTheRefreshWarmsBehindACachedPaintWithoutARender() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier)
        detail.viewerLogin = "octocat"
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        try await fixture.wait(
            until: { fixture.service.diffCallCount == 1 },
            "the warm refresh never ran"
        )

        XCTAssertEqual(fixture.service.detailCallCount, 1)
        guard case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
        // The render a real card would have done finds the refresh already spent.
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        XCTAssertEqual(fixture.service.detailCallCount, 1)
    }

    /// A cold cache is the case the warm matters most for: there are no hunks to paint, so without
    /// it the card opens on a loading caption over two round trips.
    func testAColdCacheWarmsItsRefreshToo() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        try await fixture.wait(
            until: {
                if case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) {
                    return true
                }
                return false
            },
            "the warm refresh never loaded the preview"
        )

        XCTAssertEqual(fixture.service.detailCallCount, 1)
    }

    /// Several threads hold proposals at once. Every one of them warms — none is dropped — and
    /// they go one at a time, so launch does not open a `gh` pair per unresolved proposal together.
    func testEveryPendingProposalWarmsOneAtATime() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")],
            secondProposal: true
        )
        let detailGate = PullRequestsServiceGate()
        fixture.service.detailGate = detailGate
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        try await fixture.wait(
            until: { fixture.service.detailCallCount == 1 },
            "the warm never started"
        )
        // The stub counts a call before it waits on the gate, so a fan-out would already read 2.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(fixture.service.detailCallCount, 1)

        detailGate.open()

        try await fixture.wait(
            until: { fixture.service.detailCallCount == 2 },
            "the second thread's proposal never warmed"
        )
        try await fixture.wait(
            until: {
                if case .loaded? = fixture.coordinator.preview(
                    forProposalID: ReviewProposalFixture.secondProposalID
                ) {
                    return true
                }
                return false
            },
            "the second thread's proposal never loaded"
        )
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
        fixture.service.detailResult = .failure(.rateLimited)
        // Armed before the first suspension, because the warm refresh this asserts on is the one
        // chained behind the paint rather than one a render asked for.
        let recorder = fixture.cardStateRecorder()

        // The paint posts once and the failed refresh behind it a second time.
        try await fixture.wait(for: recorder, count: 2)

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

        // No second render: staging happens in the pull request pane, so the reload has to start
        // from the invalidation or the card stays blank until the transcript is looked at again.
        try await fixture.wait(
            until: { fixture.service.detailCallCount == 2 },
            "the staged comment never reloaded the diff"
        )
        try await fixture.waitForPreview()
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
        // Detail is gated, so no round trip the warm opened can have produced these hunks.
        XCTAssertEqual(fixture.service.diffCallCount, 0)
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
        // Held closed so the warm refresh cannot resolve the card either way.
        fixture.service.detailGate = PullRequestsServiceGate()

        let recorder = fixture.cardStateRecorder()
        try await Task.sleep(nanoseconds: 100_000_000)

        if case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) {
            XCTFail("expected the mismatched entry not to paint")
        }
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
    /// that a preview outlives the launch that loaded it. The reload starts from the invalidation
    /// rather than the next render, so the card is not left blank until the thread is reopened.
    func testARemoteChangeInvalidatesThePaintedPreviewAndReloadsIt() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        try await fixture.waitForCachedPaint()
        // The stub's default detail is a failure, so the warm leaves the cached paint standing.
        try await fixture.wait(
            until: { fixture.service.detailCallCount == 1 },
            "the warm refresh never ran"
        )

        fixture.announceRemoteChange()

        try await fixture.wait(
            until: { fixture.service.detailCallCount == 2 },
            "the invalidation never reloaded the preview"
        )
        // Never repainted from cache: those are exactly the hunks the announcement invalidated.
        if case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) {
            XCTFail("expected the announcement to drop the hunks the card drew")
        }
    }

    /// One agent turn answers and resolves several threads in a row, and each is its own
    /// announcement; reloading per announcement would cost a `gh` detail-plus-diff pair each.
    func testABurstOfAnnouncementsReloadsThePreviewOnce() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments),
            // Orders of magnitude longer than draining four buffered announcements takes, so what
            // this asserts is the debounce and not which task the cooperative pool happened to
            // resume first — a zero window would let each announcement's reload fire before the
            // next arrived and still look coalesced on an idle machine.
            remoteReloadDelay: .milliseconds(200)
        )
        try await fixture.waitForCachedPaint()
        try await fixture.wait(
            until: { fixture.service.detailCallCount == 1 },
            "the warm refresh never ran"
        )

        for _ in 0..<4 {
            fixture.announceRemoteChange()
        }

        try await fixture.wait(
            until: { fixture.service.detailCallCount == 2 },
            "the burst never reloaded the preview"
        )
        // Two debounce windows: long enough for three more reloads had the burst not coalesced.
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(fixture.service.detailCallCount, 2)
    }

    /// An announcement for a different pull request leaves this card alone.
    func testARemoteChangeForAnotherPullRequestLeavesThePreviewAlone() async throws {
        let comments = [ReviewProposalFixture.stagedComment(line: 1, body: "Guard this.")]
        let fixture = try ReviewProposalFixture(
            comments: comments,
            cachedEntry: ReviewProposalFixture.seededEntry(for: comments)
        )
        try await fixture.waitForCachedPaint()

        fixture.announceRemoteChange(
            identifier: PullRequestIdentifier(owner: "octo", repo: "beta", number: 99)
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case .loaded? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            return XCTFail("expected the preview to survive an unrelated announcement")
        }
    }
}
