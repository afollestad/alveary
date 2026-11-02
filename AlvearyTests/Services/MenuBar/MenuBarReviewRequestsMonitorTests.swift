import Foundation
import XCTest

@testable import Alveary

@MainActor
final class MenuBarReviewRequestsMonitorTests: XCTestCase {
    private let interval: Duration = .seconds(300)
    private let alpha = makePullRequestSummary(
        number: 1, title: "Alpha", updatedAt: Date(timeIntervalSince1970: 2_000), isReviewRequested: true
    )
    private let beta = makePullRequestSummary(
        number: 2, title: "Beta", updatedAt: Date(timeIntervalSince1970: 1_000), isReviewRequested: true
    )

    func testInactiveMonitorNeverReads() async {
        let fixture = MenuBarReviewRequestsMonitorFixture(rows: [alpha])

        fixture.monitor.configure(isActive: false, interval: interval)
        await settle()

        XCTAssertEqual(fixture.monitor.phase, .inactive)
        XCTAssertEqual(fixture.service.listCallCount, 0)
        XCTAssertTrue(fixture.sleeper.pendingDurations().isEmpty)
    }

    func testActivationReadsOpenReviewRequestsAtOnceThenEveryInterval() async throws {
        let fixture = MenuBarReviewRequestsMonitorFixture(rows: [alpha, beta])

        fixture.monitor.configure(isActive: true, interval: interval)
        XCTAssertEqual(fixture.monitor.phase, .loading)
        try await waitUntil("the first read lands") { fixture.monitor.phase == .loaded }

        XCTAssertEqual(
            fixture.service.listRequests,
            [.init(buckets: [.reviewRequested], status: .open, options: .firstPage)]
        )
        XCTAssertEqual(fixture.service.listOrigins, [MenuBarReviewRequestsMonitor.requestOrigin])
        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [alpha.id, beta.id])

        try await waitUntil("the next read is scheduled") { fixture.sleeper.pendingDurations() == [self.interval] }
        fixture.sleeper.resumeNext()
        try await waitUntil("the interval elapses into a second read") { fixture.service.listCallCount == 2 }
    }

    func testUnchangedConfigurationDoesNotReadAgain() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha], interval: interval)

        fixture.monitor.configure(isActive: true, interval: interval)
        await settle()

        XCTAssertEqual(fixture.service.listCallCount, 1)
        XCTAssertEqual(fixture.sleeper.pendingDurations(), [interval])
    }

    func testIntervalChangeReadsAtOnceAndReschedules() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha], interval: interval)

        fixture.monitor.configure(isActive: true, interval: .seconds(60))

        try await waitUntil("the restart reads") { fixture.service.listCallCount == 2 }
        try await waitUntil("only the new interval is pending") {
            fixture.sleeper.pendingDurations() == [.seconds(60)]
        }
    }

    func testDeactivationClearsRowsAndStopsTheLoop() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha], interval: interval)
        let changes = fixture.recordChanges()

        fixture.monitor.configure(isActive: false, interval: interval)

        XCTAssertEqual(fixture.monitor.phase, .inactive)
        XCTAssertTrue(fixture.monitor.visibleSummaries.isEmpty)
        XCTAssertEqual(changes.count, 1)
        try await waitUntil("the pending sleep is cancelled") { fixture.sleeper.pendingDurations().isEmpty }
    }

    func testIgnoredPullRequestsAreHiddenAndIgnoringOneNotifiesWithoutARead() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha, beta], interval: interval)
        let changes = fixture.recordChanges()
        fixture.service.subscriptionStatesResult = .success([
            alpha.id: PullRequestSubscriptionSnapshot(
                nodeID: "PR_alpha",
                summary: alpha,
                subscription: .subscribed,
                viewerCanSubscribe: true
            )
        ])

        try await fixture.ignoreService.setIgnored(true, for: alpha.id)

        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [beta.id])
        try await waitUntil("the ignore list change is announced") { changes.count > 0 }
        XCTAssertEqual(fixture.service.listCallCount, 1)
    }

    func testFailureAfterASuccessKeepsTheLastRows() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha], interval: interval)
        fixture.service.listResult = .failure(.transport("offline"))

        fixture.monitor.refreshNow()
        try await waitUntil("the failing read lands") { fixture.service.listCallCount == 2 }
        await settle()

        XCTAssertEqual(fixture.monitor.phase, .loaded)
        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [alpha.id])
    }

    func testFailureBeforeAnySuccessReadsAsFailedUntilARetrySucceeds() async throws {
        let fixture = MenuBarReviewRequestsMonitorFixture(rows: [alpha])
        fixture.service.listResult = .failure(.notAuthenticated)

        fixture.monitor.configure(isActive: true, interval: interval)
        try await waitUntil("the first read fails") { fixture.monitor.phase == .failed }

        fixture.service.listResult = .success(PullRequestListResult(summaries: [alpha], warnings: []))
        try await waitUntil("the retry is scheduled") { fixture.sleeper.pendingDurations() == [self.interval] }
        fixture.sleeper.resumeNext()
        try await waitUntil("the retry lands") { fixture.monitor.phase == .loaded }
        XCTAssertEqual(fixture.monitor.visibleSummaries.map(\.id), [alpha.id])
    }

    func testRateLimitWaitsUntilGitHubsRetryTime() async throws {
        let fixture = MenuBarReviewRequestsMonitorFixture(rows: [alpha])
        fixture.service.listResult = .failure(.rateLimit(GitHubRateLimit(
            resource: "graphql",
            isSecondary: false,
            retryAt: fixture.now.addingTimeInterval(900)
        )))

        fixture.monitor.configure(isActive: true, interval: interval)

        try await waitUntil("the wait runs to retryAt") { fixture.sleeper.pendingDurations() == [.seconds(900)] }
    }

    func testListRowAnnouncementsRefreshAfterTheDebounce() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha], interval: interval)

        fixture.announce(affectsListRow: false)
        await settle()
        XCTAssertEqual(fixture.sleeper.pendingDurations(), [interval])

        fixture.announce(affectsListRow: true)
        try await waitUntil("the debounce starts") {
            fixture.sleeper.pendingDurations().contains(fixture.remoteChangeDelay)
        }
        fixture.sleeper.resumeNext(matching: fixture.remoteChangeDelay)

        try await waitUntil("the announcement reads again") { fixture.service.listCallCount == 2 }
    }

    func testDisabledPollingRunsTheLifecycleWithoutReachingGitHub() async throws {
        let fixture = MenuBarReviewRequestsMonitorFixture(rows: [alpha], pollsGitHub: false)

        fixture.monitor.configure(isActive: true, interval: interval)

        try await waitUntil("the loop still schedules") { fixture.sleeper.pendingDurations() == [self.interval] }
        XCTAssertEqual(fixture.service.listCallCount, 0)
        XCTAssertEqual(fixture.monitor.phase, .loading)
    }

    func testStopCancelsTheLoopSynchronously() async throws {
        let fixture = try await MenuBarReviewRequestsMonitorFixture.loaded(rows: [alpha], interval: interval)

        fixture.monitor.stop()

        XCTAssertEqual(fixture.monitor.phase, .inactive)
        try await waitUntil("the pending sleep is cancelled") { fixture.sleeper.pendingDurations().isEmpty }
        fixture.announce(affectsListRow: true)
        await settle()
        XCTAssertTrue(fixture.sleeper.pendingDurations().isEmpty)
    }

    /// Gives any spawned task a chance to run, for asserting that nothing happened.
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func waitUntil(
        _ description: String,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        try await scheduledTaskLifecycleWaitUntil(description, condition: condition)
    }
}

@MainActor
private struct MenuBarReviewRequestsMonitorFixture {
    let service = StubPullRequestsService()
    let sleeper = ScheduledLifecycleTestSleeper()
    let notificationCenter = NotificationCenter()
    let now = Date(timeIntervalSince1970: 10_000)
    let remoteChangeDelay: Duration = .seconds(2)
    let ignoreService: PullRequestIgnoreService
    let monitor: MenuBarReviewRequestsMonitor

    init(rows: [PullRequestSummary], pollsGitHub: Bool = true) {
        service.listResult = .success(PullRequestListResult(summaries: rows, warnings: []))
        ignoreService = PullRequestIgnoreService(service: service, store: nil)
        let sleeper = sleeper
        let now = now
        monitor = MenuBarReviewRequestsMonitor(
            service: service,
            ignoreService: ignoreService,
            notificationCenter: notificationCenter,
            pollsGitHub: pollsGitHub,
            remoteChangeDelay: remoteChangeDelay,
            now: { now },
            sleep: { try await sleeper.sleep($0) }
        )
    }

    /// Active, with its first read landed and the next interval pending.
    static func loaded(rows: [PullRequestSummary], interval: Duration) async throws -> Self {
        let fixture = Self(rows: rows)
        fixture.monitor.configure(isActive: true, interval: interval)
        try await scheduledTaskLifecycleWaitUntil("the first read lands and the next is scheduled") {
            fixture.monitor.phase == .loaded && fixture.sleeper.pendingDurations() == [interval]
        }
        return fixture
    }

    func recordChanges() -> ChangeCounter {
        let counter = ChangeCounter()
        monitor.onChange = { counter.count += 1 }
        return counter
    }

    func announce(affectsListRow: Bool) {
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: nil,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 1),
                    affectsListRow: affectsListRow
                )
            ]
        )
    }

    @MainActor
    final class ChangeCounter {
        var count = 0
    }
}
