import Foundation
import XCTest

@testable import Alveary

@MainActor
final class PullRequestIgnoreServiceTests: XCTestCase {
    private let alpha = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 1)
    private let beta = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 2)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Ignoring

    func testIgnoreUnsubscribesAndPersistsAcrossLaunches() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .subscribed)])
        let fileURL = makeStoreURL()
        let service = makeService(stub: stub, fileURL: fileURL)

        try await service.setIgnored(true, for: alpha)

        XCTAssertEqual(stub.subscriptionLookups, [[alpha]])
        XCTAssertEqual(stub.subscriptionUpdates, [.init(nodeID: "PR_1", subscribed: false)])
        XCTAssertEqual(service.effectiveIgnoredIDs, [alpha])
        XCTAssertTrue(service.pendingIDs.isEmpty)

        await service.waitForPendingSave()
        let relaunched = makeService(stub: stub, fileURL: fileURL)
        await relaunched.loadIfNeeded()
        XCTAssertTrue(relaunched.isIgnored(alpha))
    }

    func testIgnoreReadsAsDoneWhileInFlight() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .subscribed)])
        let gate = PullRequestsServiceGate()
        stub.updateSubscriptionGate = gate
        let service = makeService(stub: stub)

        let task = Task { try await service.setIgnored(true, for: alpha) }
        await waitFor { service.pendingIDs.contains(alpha) }

        XCTAssertTrue(service.isIgnored(alpha))
        gate.open()
        try await task.value
        XCTAssertTrue(service.isIgnored(alpha))
        XCTAssertTrue(service.pendingIDs.isEmpty)
    }

    func testRejectedIgnoreRevertsAndIsNotPersisted() async {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .subscribed)])
        stub.updateSubscriptionResult = .failure(.insufficientScopes)
        let service = makeService(stub: stub)

        await assertThrows(.insufficientScopes) {
            try await service.setIgnored(true, for: alpha)
        }

        XCTAssertFalse(service.isIgnored(alpha))
        XCTAssertTrue(service.pendingIDs.isEmpty)
    }

    /// Persisting an ignore GitHub refused to keep would only have the next sync undo it.
    func testIgnoreThatStaysSubscribedFails() async {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .subscribed)])
        stub.updateSubscriptionResult = .success(.subscribed)
        let service = makeService(stub: stub)

        await assertThrows(.transport("GitHub kept you subscribed to octo/alpha#1.")) {
            try await service.setIgnored(true, for: alpha)
        }
        XCTAssertFalse(service.isIgnored(alpha))
    }

    func testIgnoreFailsWhenGitHubDoesNotReturnThePullRequest() async {
        let stub = StubPullRequestsService()
        let service = makeService(stub: stub)

        await assertThrows(.transport("GitHub did not return octo/alpha#1.")) {
            try await service.setIgnored(true, for: alpha)
        }
        XCTAssertTrue(stub.subscriptionUpdates.isEmpty)
    }

    func testUnignoreResubscribes() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .unsubscribed)])
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))
        await service.loadIfNeeded()

        try await service.setIgnored(false, for: alpha)

        XCTAssertEqual(stub.subscriptionUpdates, [.init(nodeID: "PR_1", subscribed: true)])
        XCTAssertFalse(service.isIgnored(alpha))
    }

    // MARK: - Sync

    func testSyncDropsMergedAndClosedAndReturnsFreshRows() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([
            alpha: snapshot(alpha, status: .merged, subscription: .unsubscribed),
            beta: snapshot(beta, status: .open, subscription: .unsubscribed)
        ])
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha), entry(beta)]))
        clock.addTimeInterval(3_600)

        let summaries = await service.reconcileIfNeeded(force: false)

        XCTAssertEqual(service.effectiveIgnoredIDs, [beta])
        XCTAssertEqual(Set(summaries.map(\.id)), [alpha, beta])
        XCTAssertEqual(summaries.first { $0.id == alpha }?.status, .merged)
    }

    /// Subscribed again, on github.com or by GitHub itself: either is a reason to see it again.
    func testSyncUnignoresWhatGitHubResubscribed() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .subscribed)])
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))
        clock.addTimeInterval(3_600)

        _ = await service.reconcileIfNeeded(force: false)

        XCTAssertFalse(service.isIgnored(alpha))
    }

    /// A read that raced the unsubscribe must not undo the ignore.
    func testSyncKeepsAResubscribedEntryIgnoredWithinTheGracePeriod() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .subscribed)])
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))
        clock.addTimeInterval(PullRequestIgnoreService.resubscribeGrace - 1)

        _ = await service.reconcileIfNeeded(force: false)

        XCTAssertTrue(service.isIgnored(alpha))
    }

    /// A SAML-hidden or deleted pull request is kept until it has been unseen for the retention.
    func testSyncKeepsAnUnreturnedEntryUntilTheRetentionPasses() async throws {
        let stub = StubPullRequestsService()
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))
        clock.addTimeInterval(PullRequestIgnoreService.unseenRetention - 1)

        _ = await service.reconcileIfNeeded(force: true)
        XCTAssertTrue(service.isIgnored(alpha))

        clock.addTimeInterval(2)
        _ = await service.reconcileIfNeeded(force: true)
        XCTAssertFalse(service.isIgnored(alpha))
    }

    /// Seeing it open and unsubscribed restarts the retention clock.
    func testSyncStampsWhenItLastSawAnEntry() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .unsubscribed)])
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))
        clock.addTimeInterval(PullRequestIgnoreService.unseenRetention - 1)
        _ = await service.reconcileIfNeeded(force: true)

        stub.subscriptionStatesResult = .success([:])
        clock.addTimeInterval(2)
        _ = await service.reconcileIfNeeded(force: true)

        XCTAssertTrue(service.isIgnored(alpha))
    }

    func testSyncIsThrottledUnlessForced() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .success([alpha: snapshot(alpha, subscription: .unsubscribed)])
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))

        _ = await service.reconcileIfNeeded(force: false)
        clock.addTimeInterval(PullRequestIgnoreService.reconcileInterval - 1)
        _ = await service.reconcileIfNeeded(force: false)
        XCTAssertEqual(stub.subscriptionLookups.count, 1)

        _ = await service.reconcileIfNeeded(force: true)
        XCTAssertEqual(stub.subscriptionLookups.count, 2)

        clock.addTimeInterval(PullRequestIgnoreService.reconcileInterval)
        _ = await service.reconcileIfNeeded(force: false)
        XCTAssertEqual(stub.subscriptionLookups.count, 3)
    }

    func testSyncSpendsNothingWithNothingIgnored() async {
        let stub = StubPullRequestsService()
        let service = makeService(stub: stub)

        let summaries = await service.reconcileIfNeeded(force: true)

        XCTAssertTrue(summaries.isEmpty)
        XCTAssertTrue(stub.subscriptionLookups.isEmpty)
    }

    /// A failed read is not stamped, so the next refresh tries again rather than waiting it out.
    func testFailedSyncChangesNothingAndRetriesNextTime() async throws {
        let stub = StubPullRequestsService()
        stub.subscriptionStatesResult = .failure(.transport("offline"))
        let service = makeService(stub: stub, fileURL: await makeSeededStore([entry(alpha)]))

        let summaries = await service.reconcileIfNeeded(force: false)
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertTrue(service.isIgnored(alpha))

        _ = await service.reconcileIfNeeded(force: false)
        XCTAssertEqual(stub.subscriptionLookups.count, 2)
    }

    func testCorruptStoreLoadsEmpty() async throws {
        let fileURL = makeStoreURL()
        try Data("not json".utf8).write(to: fileURL)
        let service = makeService(stub: StubPullRequestsService(), fileURL: fileURL)

        await service.loadIfNeeded()

        XCTAssertTrue(service.effectiveIgnoredIDs.isEmpty)
    }

    // MARK: - Helpers

    /// Main-actor twin of `assertPullRequestsServiceThrows`, whose nonisolated closure cannot
    /// capture the main-actor service under test.
    private func assertThrows(
        _ expected: PullRequestsServiceError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PullRequestsServiceError, expected, file: file, line: line)
        }
    }

    private func makeService(stub: StubPullRequestsService, fileURL: URL? = nil) -> PullRequestIgnoreService {
        PullRequestIgnoreService(
            service: stub,
            store: IgnoredPullRequestsStore(fileURL: fileURL ?? makeStoreURL()),
            now: { [unowned self] in clock }
        )
    }

    private func makeStoreURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ignored-prs-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeSeededStore(_ entries: [IgnoredPullRequestEntry]) async -> URL {
        let url = makeStoreURL()
        await IgnoredPullRequestsStore(fileURL: url).save(IgnoredPullRequestsSnapshot(entries: entries, lastReconciledAt: nil))
        return url
    }

    private func entry(_ id: PullRequestIdentifier) -> IgnoredPullRequestEntry {
        IgnoredPullRequestEntry(id: id, ignoredAt: clock, lastSeenAt: clock)
    }

    private func snapshot(
        _ id: PullRequestIdentifier,
        status: PullRequestStatus = .open,
        subscription: PullRequestSubscriptionState?
    ) -> PullRequestSubscriptionSnapshot {
        PullRequestSubscriptionSnapshot(
            nodeID: "PR_\(id.number)",
            summary: makePullRequestSummary(number: id.number, repo: id.nameWithOwner, status: status),
            subscription: subscription,
            viewerCanSubscribe: true
        )
    }
}
