import Foundation
import XCTest

@testable import Alveary

@MainActor
final class MenuBarAgentReviewHandoffsTests: XCTestCase {
    private let alpha = PullRequestIdentifier(owner: "Octo", repo: "Alpha", number: 1)

    func testAReviewRouteHidesItsPullRequestWhateverTheCasing() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()

        fixture.activity.begin(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 1), kind: .review)

        XCTAssertTrue(fixture.handoffs.hides(alpha))
        XCTAssertEqual(fixture.changes, [false])
    }

    func testAnAddressFeedbackRouteIsNotAReviewHandoff() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()

        fixture.activity.begin(alpha, kind: .addressFeedback)

        XCTAssertFalse(fixture.handoffs.hides(alpha))
        XCTAssertTrue(fixture.changes.isEmpty)
    }

    func testADiscardedProposalReturnsItsPullRequestAtOnce() {
        let fixture = HandoffsFixture()
        fixture.proposals = [alpha]
        fixture.handoffs.start()
        XCTAssertTrue(fixture.handoffs.hides(alpha))

        fixture.proposals = []
        fixture.notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: nil)

        XCTAssertFalse(fixture.handoffs.hides(alpha))
        XCTAssertEqual(fixture.changes, [false])
    }

    func testACancelledAgentReturnsItsPullRequestAtOnce() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()
        fixture.activity.begin(alpha, kind: .review)

        fixture.activity.end(alpha, kind: .review)

        XCTAssertFalse(fixture.handoffs.hides(alpha))
        XCTAssertEqual(fixture.changes, [false, false])
    }

    func testASubmittedReviewStaysHiddenUntilItsReleaseSettles() {
        let fixture = HandoffsFixture()
        fixture.proposals = [alpha]
        fixture.handoffs.start()

        // `confirm`'s order: the submit is announced, then the envelope clears.
        fixture.announceChange(alpha)
        fixture.proposals = []
        fixture.notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: nil)

        XCTAssertTrue(fixture.handoffs.hides(alpha))
        XCTAssertEqual(fixture.changes, [true])
    }

    func testAChangeAnnouncedBeforeTheHandoffDoesNotSettleItsRelease() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()

        fixture.announceChange(alpha)
        fixture.activity.begin(alpha, kind: .review)
        fixture.activity.end(alpha, kind: .review)

        XCTAssertFalse(fixture.handoffs.hides(alpha))
    }

    func testTheAgentFinishingIntoAProposalIsNotARelease() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()
        fixture.activity.begin(alpha, kind: .review)

        fixture.proposals = [alpha]
        fixture.notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: nil)
        fixture.activity.end(alpha, kind: .review)

        XCTAssertTrue(fixture.handoffs.hides(alpha))
        XCTAssertFalse(fixture.changes.contains(true))
    }

    func testOnlyAReadStartedAfterTheSettleLiftsASettlingHide() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()
        fixture.activity.begin(alpha, kind: .review)
        fixture.announceChange(alpha)
        fixture.activity.end(alpha, kind: .review)
        let releasedAt = fixture.clock.now

        fixture.handoffs.readFinished(startedAt: releasedAt.addingTimeInterval(fixture.handoffs.releaseSettle - 1))
        XCTAssertTrue(fixture.handoffs.hides(alpha))

        fixture.handoffs.readFinished(startedAt: releasedAt.addingTimeInterval(fixture.handoffs.releaseSettle))
        XCTAssertFalse(fixture.handoffs.hides(alpha))
    }

    func testHandingOffAgainCancelsAPendingRelease() {
        let fixture = HandoffsFixture()
        fixture.handoffs.start()
        fixture.activity.begin(alpha, kind: .review)
        fixture.announceChange(alpha)
        fixture.activity.end(alpha, kind: .review)
        let firstRelease = fixture.clock.now

        fixture.clock.now = firstRelease.addingTimeInterval(5)
        fixture.activity.begin(alpha, kind: .review)
        fixture.announceChange(alpha)
        fixture.activity.end(alpha, kind: .review)
        fixture.handoffs.readFinished(startedAt: firstRelease.addingTimeInterval(fixture.handoffs.releaseSettle))

        XCTAssertTrue(fixture.handoffs.hides(alpha), "Released again just now, so this read is too early")
    }

    func testStopForgetsEverythingAndStopsFollowing() {
        let fixture = HandoffsFixture()
        fixture.proposals = [alpha]
        fixture.handoffs.start()

        fixture.handoffs.stop()
        fixture.activity.begin(PullRequestIdentifier(owner: "octo", repo: "beta", number: 2), kind: .review)

        XCTAssertFalse(fixture.handoffs.hides(alpha))
        XCTAssertTrue(fixture.changes.isEmpty)
    }
}

@MainActor
private final class HandoffsFixture {
    let notificationCenter = NotificationCenter()
    let clock = MenuBarTestClock()
    let activity: PullRequestAgenticThreadActivity
    var proposals: Set<PullRequestIdentifier> = []
    var changes: [Bool] = []
    private(set) var handoffs: MenuBarAgentReviewHandoffs!

    init() {
        activity = PullRequestAgenticThreadActivity(notificationCenter: notificationCenter)
        let clock = clock
        handoffs = MenuBarAgentReviewHandoffs(
            activity: activity,
            pendingProposalIdentifiers: { [unowned self] in self.proposals },
            notificationCenter: notificationCenter,
            now: { clock.now }
        )
        handoffs.onChange = { [unowned self] released in self.changes.append(released) }
    }

    /// What `PullRequestReviewProposalCoordinator.confirm` posts once a review is live on GitHub.
    func announceChange(_ identifier: PullRequestIdentifier) {
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: nil,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: identifier,
                    affectsListRow: true
                )
            ]
        )
    }
}
