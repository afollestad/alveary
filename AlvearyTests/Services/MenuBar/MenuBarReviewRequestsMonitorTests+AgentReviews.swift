import Foundation
import XCTest

@testable import Alveary

// Pull requests handed to an agent review, and when a released one returns.
extension MenuBarReviewRequestsMonitorTests {
    func testACancelledAgentReviewReturnsItsPullRequestWithoutARead() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha, beta], interval: interval)
        let changes = fixture.recordChanges()

        fixture.activity.begin(alpha.id, kind: .review)
        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [beta.id])

        fixture.activity.end(alpha.id, kind: .review)

        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(changes.count, 2)
        await settle()
        XCTAssertEqual(fixture.service.listCallCount, 1)
        XCTAssertEqual(fixture.sleeper.pendingDurations(), [interval])
    }

    func testASubmittedReviewKeepsItsPullRequestHiddenUntilTheSettlingRead() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha, beta], interval: interval)
        fixture.activity.begin(alpha.id, kind: .review)

        fixture.announce(affectsListRow: true)
        fixture.activity.end(alpha.id, kind: .review)
        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [beta.id])
        let settle = Duration.seconds(10)
        try await waitUntil("the settling read is scheduled") {
            fixture.sleeper.pendingDurations().contains(settle)
        }
        fixture.clock.now = fixture.clock.now.addingTimeInterval(10)
        fixture.sleeper.resumeNext(matching: settle)

        // The stub still lists it, so the settling read is what brings it back.
        try await waitUntil("the settling read returns it") {
            fixture.monitor.visibleSummaries.map(\.id) == [self.alpha.id, self.beta.id]
        }
    }

    func testAFailedSettlingReadStillReturnsASubmittedReviewsPullRequest() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha, beta], interval: interval)
        fixture.activity.begin(alpha.id, kind: .review)
        // The quota cooldown fails every read without reaching GitHub until `retryAt`.
        fixture.service.listResult = .failure(.rateLimit(GitHubRateLimit(
            resource: "graphql",
            isSecondary: false,
            retryAt: fixture.now.addingTimeInterval(3_600)
        )))

        fixture.announce(affectsListRow: true)
        fixture.activity.end(alpha.id, kind: .review)
        let settle = Duration.seconds(10)
        try await waitUntil("the settling read is scheduled") {
            fixture.sleeper.pendingDurations().contains(settle)
        }
        fixture.clock.now = fixture.clock.now.addingTimeInterval(10)
        fixture.sleeper.resumeNext(matching: settle)

        try await waitUntil("the failed read returns the last rows") {
            fixture.monitor.visibleSummaries.map(\.id) == [self.alpha.id, self.beta.id]
        }
        XCTAssertEqual(fixture.monitor.phase, .loaded)
    }

    func testAReadBeforeTheSettleKeepsASubmittedReviewsPullRequestHidden() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha, beta], interval: interval)
        fixture.activity.begin(alpha.id, kind: .review)
        fixture.announce(affectsListRow: true)
        fixture.activity.end(alpha.id, kind: .review)

        // The announcement's own refresh reads two seconds later, ahead of the settle.
        fixture.monitor.refreshNow()
        try await waitUntil("the early read lands") { fixture.service.listCallCount == 2 }
        await settle()

        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [beta.id])
    }
}
