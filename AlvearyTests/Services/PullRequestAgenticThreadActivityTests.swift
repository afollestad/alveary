import Foundation
import XCTest

@testable import Alveary

/// The phase machine behind the review footer's spinner: a route is working from the click until
/// the thread it spawned finishes its first turn, and every way that can end is covered here.
@MainActor
final class PullRequestAgenticThreadActivityTests: XCTestCase {
    private let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    private let other = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 8)

    private func makeActivity(
        startupGrace: Duration = .seconds(30),
        currentSignal: @escaping @MainActor (String) -> ActivitySignal = { _ in .neutral }
    ) -> (PullRequestAgenticThreadActivity, NotificationCenter) {
        let center = NotificationCenter()
        let activity = PullRequestAgenticThreadActivity(
            notificationCenter: center,
            startupGrace: startupGrace,
            currentSignal: currentSignal
        )
        return (activity, center)
    }

    private func post(
        _ signal: ActivitySignal?,
        conversationID: String,
        on center: NotificationCenter
    ) {
        var userInfo: [String: Any] = [AgentStatusChangedKey.conversationID: conversationID]
        if let signal {
            userInfo[AgentStatusChangedKey.signal] = signal
        }
        center.post(name: .agentStatusChanged, object: nil, userInfo: userInfo)
    }

    /// Working before a thread exists at all — the click has to light the button up on its own
    /// turn, long before there is a conversation to follow.
    func testBeginMarksTheRouteWorkingWithNoConversationYet() {
        let (activity, _) = makeActivity()

        activity.begin(identifier, kind: .review)

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
        XCTAssertEqual(activity.workingKinds(for: identifier), [.review])
    }

    func testTheRouteEndsWhenItsFirstTurnGoesIdle() {
        let (activity, center) = makeActivity()
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)

        post(.busy, conversationID: "c1", on: center)
        XCTAssertTrue(activity.isWorking(identifier, kind: .review))

        post(.idle, conversationID: "c1", on: center)
        XCTAssertFalse(activity.isWorking(identifier, kind: .review))
    }

    /// An approval pause is the run needing the user, not the run being over.
    func testAWaitingForUserPauseKeepsTheRouteWorking() {
        let (activity, center) = makeActivity()
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
        post(.busy, conversationID: "c1", on: center)

        post(.waitingForUser, conversationID: "c1", on: center)

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
    }

    /// A run can end without reaching `.idle` — the thread errors, is stopped, or is deleted, and
    /// `clearStatus` posts `.neutral` for that last one.
    func testEveryNonWorkingSignalEndsAPromotedRoute() {
        for signal in [ActivitySignal.idle, .neutral, .stopped, .error] {
            let (activity, center) = makeActivity()
            activity.begin(identifier, kind: .review)
            activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
            post(.busy, conversationID: "c1", on: center)

            post(signal, conversationID: "c1", on: center)

            XCTAssertFalse(
                activity.isWorking(identifier, kind: .review),
                "\(signal) should end the route"
            )
        }
    }

    /// The runtime writes `.idle` at buffer install when a spawn carries no immediate turn, so an
    /// unlatched entry would end before its turn began.
    func testANonWorkingSignalBeforeThePromotionIsIgnored() {
        let (activity, center) = makeActivity()
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)

        post(.idle, conversationID: "c1", on: center)

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
    }

    /// `DefaultNotificationManager` shares this bus for unread flips, posting the conversation with
    /// no signal at all.
    func testAPostWithNoSignalIsNotATransition() {
        let (activity, center) = makeActivity()
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
        post(.busy, conversationID: "c1", on: center)

        post(nil, conversationID: "c1", on: center)

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
    }

    func testAnotherConversationsSignalsAreIgnored() {
        let (activity, center) = makeActivity()
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
        post(.busy, conversationID: "c1", on: center)

        post(.idle, conversationID: "c2", on: center)

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
    }

    /// `start` creates its dispatch task before it returns, so a fast turn can report `.busy`
    /// before the caller has attached — and that notification lands while no entry names the
    /// conversation. Re-reading the live signal at attach is what recovers it.
    func testAttachPromotesWhenTheTurnAlreadyStarted() {
        let (activity, center) = makeActivity(currentSignal: { _ in .busy })
        activity.begin(identifier, kind: .review)

        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
        // Promoted despite never seeing a `.busy` post, so the next idle ends it.
        post(.idle, conversationID: "c1", on: center)

        XCTAssertFalse(activity.isWorking(identifier, kind: .review))
    }

    /// A spawn whose provider never starts reports nothing at all, so only the grace can end it.
    func testTheStartupGraceDropsARunThatNeverStarts() async {
        let (activity, _) = makeActivity(startupGrace: .milliseconds(10))
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)

        activity.armStartupGrace(identifier, kind: .review)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(activity.isWorking(identifier, kind: .review))
    }

    /// The grace only bounds the wait *for* a turn; once one is running it must never fire.
    func testTheStartupGraceIsANoOpOnceTheTurnIsRunning() async {
        let (activity, center) = makeActivity(startupGrace: .milliseconds(10))
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
        post(.busy, conversationID: "c1", on: center)

        activity.armStartupGrace(identifier, kind: .review)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
    }

    /// A turn that took longer than the grace to appear is still a turn; the live signal gets the
    /// last word before the entry is dropped.
    func testAnExpiringGraceDefersToALateStartedTurn() async {
        let (activity, _) = makeActivity(startupGrace: .milliseconds(10), currentSignal: { _ in .busy })
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)

        activity.armStartupGrace(identifier, kind: .review)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(activity.isWorking(identifier, kind: .review))
    }

    /// The two halves of a pull request's life are separate work, and separate pull requests are
    /// more separate still.
    func testRoutesAndPullRequestsTrackIndependently() {
        let (activity, center) = makeActivity()
        activity.begin(identifier, kind: .review)
        activity.attach(conversationID: "c1", identifier: identifier, kind: .review)
        activity.begin(identifier, kind: .addressFeedback)
        activity.attach(conversationID: "c2", identifier: identifier, kind: .addressFeedback)
        activity.begin(other, kind: .review)

        post(.busy, conversationID: "c1", on: center)
        post(.idle, conversationID: "c1", on: center)

        XCTAssertEqual(activity.workingKinds(for: identifier), [.addressFeedback])
        XCTAssertEqual(activity.workingKinds(for: other), [.review])
    }

    func testEndClearsTheRoute() {
        let (activity, _) = makeActivity()
        activity.begin(identifier, kind: .review)

        activity.end(identifier, kind: .review)

        XCTAssertFalse(activity.isWorking(identifier, kind: .review))
    }

    /// The mirror onto each pane session hangs off this, so a transition nobody announces is a
    /// spinner that never appears or never leaves.
    func testTransitionsAreAnnounced() {
        let (activity, center) = makeActivity()
        let announcements = AnnouncementCounter()
        let observer = center.addObserver(
            forName: .pullRequestAgenticThreadActivityChanged,
            object: nil,
            queue: nil
        ) { _ in
            announcements.increment()
        }
        defer { center.removeObserver(observer) }

        activity.begin(identifier, kind: .review)
        activity.end(identifier, kind: .review)

        XCTAssertEqual(announcements.count, 2)
    }
}

/// Counts announcements from a `@Sendable` observer closure, which cannot capture a `var`.
private final class AnnouncementCounter: @unchecked Sendable {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
