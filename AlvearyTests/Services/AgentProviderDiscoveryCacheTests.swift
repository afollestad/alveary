import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// The cache in front of provider discovery. Its whole job is to keep thread creation off the
/// subprocess fan-out, without ever answering a project-scoped or post-install read from memory.
final class AgentProviderDiscoveryCacheTests: XCTestCase {
    /// Counts probes and can be held open, so a test can prove coalescing rather than infer it.
    /// Its answer is settable because stale-while-revalidate makes *which* snapshot a read served
    /// the thing under test, not just how many probes ran.
    private actor ProbeCountingDiscovery: AgentProviderDiscoveryService {
        private(set) var allCallCount = 0
        private(set) var lastProjectURLs: [URL?] = []
        private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
        private var isHeld = false
        private var answer: [AgentProviderID: AgentProviderStatus] = [:]
        private(set) var cancelledCalls: Set<Int> = []

        func hold() {
            isHeld = true
        }

        func release() {
            isHeld = false
            let waiting = Array(gates.values)
            gates = [:]
            for continuation in waiting { continuation.resume() }
        }

        func release(call: Int) {
            gates.removeValue(forKey: call)?.resume()
        }

        func setAnswer(_ answer: [AgentProviderID: AgentProviderStatus]) {
            self.answer = answer
        }

        func providerStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] {
            allCallCount += 1
            let call = allCallCount
            let answer = self.answer
            lastProjectURLs.append(projectURL)
            if isHeld {
                await withCheckedContinuation { continuation in
                    gates[call] = continuation
                }
            }
            if Task.isCancelled { cancelledCalls.insert(call) }
            return answer
        }

        func installedProviderStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] { [:] }

        func availableProviderStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] { [:] }

        func modelOptions(for providerId: AgentProviderID) async -> [AgentModelOption] { [] }

        func stableProviderOrdering() async -> [AgentProviderID] { [] }
    }

    /// A clock the test advances by hand, so TTL expiry needs no sleeping.
    private final class TestClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000)

        func advance(_ interval: TimeInterval) {
            now += interval
        }
    }

    private struct Fixture {
        let service: CachingAgentProviderDiscoveryService
        let base: ProbeCountingDiscovery
        let clock: TestClock
    }

    private func makeService(timeToLive: TimeInterval = 60) -> Fixture {
        let base = ProbeCountingDiscovery()
        let clock = TestClock()
        return Fixture(
            service: CachingAgentProviderDiscoveryService(
                base: base,
                timeToLive: timeToLive,
                now: { clock.now }
            ),
            base: base,
            clock: clock
        )
    }

    func testASecondReadInsideTheWindowDoesNotProbeAgain() async {
        let fixture = makeService()

        _ = await fixture.service.providerStatuses(projectURL: nil)
        fixture.clock.advance(30)
        _ = await fixture.service.providerStatuses(projectURL: nil)

        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 1)
    }

    /// The TTL bounds staleness, not latency. A read past the window must not block on the
    /// subprocess fan-out — that is exactly the New Thread delay this decorator exists to remove.
    func testAStaleReadIsAnsweredFromTheSnapshotAndRefreshesBehindIt() async {
        let fixture = makeService()
        await fixture.base.setAnswer(Self.statuses(version: "1.0.0"))
        _ = await fixture.service.providerStatuses(projectURL: nil)

        fixture.clock.advance(61)
        await fixture.base.setAnswer(Self.statuses(version: "2.0.0"))
        await fixture.base.hold()

        let stale = await fixture.service.providerStatuses(projectURL: nil)
        XCTAssertEqual(stale[.claude]?.availability?.versionDescription, "1.0.0")

        await waitUntil("expected the stale read to have started a refresh") {
            await fixture.base.allCallCount == 2
        }
        await fixture.base.release()

        await waitUntil("expected the refresh to replace the snapshot") {
            let statuses = await fixture.service.providerStatuses(projectURL: nil)
            return statuses[.claude]?.availability?.versionDescription == "2.0.0"
        }
    }

    /// A burst of thread creations must share one probe; without coalescing each would spawn the
    /// whole `which` / `--version` / app-server fan-out.
    func testConcurrentReadsShareOneProbe() async {
        let fixture = makeService()
        await fixture.base.hold()

        async let first = fixture.service.providerStatuses(projectURL: nil)
        async let second = fixture.service.providerStatuses(projectURL: nil)
        async let third = fixture.service.providerStatuses(projectURL: nil)
        // Let all three reach the actor before the probe completes.
        try? await Task.sleep(for: .milliseconds(50))
        await fixture.base.release()
        _ = await (first, second, third)

        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 1)
    }

    /// A project-scoped read carries that project's trust state, which must never be served from
    /// a snapshot taken before the user granted it.
    func testAProjectScopedReadAlwaysPassesThrough() async {
        let fixture = makeService()
        let projectURL = URL(fileURLWithPath: "/tmp/project")

        _ = await fixture.service.providerStatuses(projectURL: projectURL)
        _ = await fixture.service.providerStatuses(projectURL: projectURL)

        let count = await fixture.base.allCallCount
        let urls = await fixture.base.lastProjectURLs
        XCTAssertEqual(count, 2)
        XCTAssertEqual(urls, [projectURL, projectURL])
    }

    /// A project-scoped read must not seed the nil-project cache either — the two answers differ.
    func testAProjectScopedReadDoesNotSeedTheSharedCache() async {
        let fixture = makeService()

        _ = await fixture.service.providerStatuses(projectURL: URL(fileURLWithPath: "/tmp/project"))
        _ = await fixture.service.providerStatuses(projectURL: nil)

        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 2)
    }

    func testInvalidateForcesTheNextReadToProbe() async {
        let fixture = makeService()

        _ = await fixture.service.providerStatuses(projectURL: nil)
        await fixture.service.invalidate()
        _ = await fixture.service.providerStatuses(projectURL: nil)

        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 2)
    }

    /// Settings invalidates while a probe may already be running. That probe started before the
    /// CLI was installed, so its answer must not become the cached one.
    func testAProbeInvalidatedMidFlightIsNotCached() async {
        let fixture = makeService()
        await fixture.base.hold()

        async let inFlight = fixture.service.providerStatuses(projectURL: nil)
        try? await Task.sleep(for: .milliseconds(50))
        await fixture.service.invalidate()
        await fixture.base.release()
        _ = await inFlight

        _ = await fixture.service.providerStatuses(projectURL: nil)
        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 2)
    }

    func testWarmFillsTheCacheSoTheFirstRealReadIsFree() async {
        let fixture = makeService()

        await fixture.service.warm()
        _ = await fixture.service.providerStatuses(projectURL: nil)

        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 1)
    }

    /// `warm()` is the one path that still blocks, so wake's re-warm resolves before the next
    /// read rather than handing it the pre-sleep snapshot.
    func testWarmRefreshesAStaleSnapshotBeforeReturning() async {
        let fixture = makeService()
        await fixture.base.setAnswer(Self.statuses(version: "1.0.0"))
        await fixture.service.warm()

        fixture.clock.advance(61)
        await fixture.base.setAnswer(Self.statuses(version: "2.0.0"))
        await fixture.service.warm()

        let statuses = await fixture.service.providerStatuses(projectURL: nil)
        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 2)
        XCTAssertEqual(statuses[.claude]?.availability?.versionDescription, "2.0.0")
    }

    func testExplicitRefreshPreservesTheLastSnapshotUntilItsReplacementIsReady() async {
        let fixture = makeService()
        await fixture.base.setAnswer(Self.statuses(version: "1.0.0"))
        await fixture.service.warm()
        await fixture.base.setAnswer(Self.statuses(version: "2.0.0"))
        await fixture.base.hold()

        let refresh = Task { await fixture.service.refresh() }
        await waitUntil("expected explicit refresh to start despite a fresh snapshot") {
            await fixture.base.allCallCount == 2
        }

        let readCompleted = expectation(description: "cached read completes while refresh is held")
        let read = Task {
            let statuses = await fixture.service.providerStatuses(projectURL: nil)
            readCompleted.fulfill()
            return statuses
        }
        await fulfillment(of: [readCompleted], timeout: 2)
        await fixture.base.release()
        let cached = await read.value
        await refresh.value
        XCTAssertEqual(cached[.claude]?.availability?.versionDescription, "1.0.0")

        let refreshed = await fixture.service.providerStatuses(projectURL: nil)
        let count = await fixture.base.allCallCount
        XCTAssertEqual(refreshed[.claude]?.availability?.versionDescription, "2.0.0")
        XCTAssertEqual(count, 2)
    }

    func testExplicitRefreshEscapesAStalledColdProbeAndRejectsItsLateAnswer() async {
        let fixture = makeService()
        await fixture.base.setAnswer(Self.statuses(version: "1.0.0"))
        await fixture.base.hold()
        let oldRead = Task { await fixture.service.providerStatuses(projectURL: nil) }
        await waitUntil("expected the original cold probe to start") {
            await fixture.base.allCallCount == 1
        }

        await fixture.base.setAnswer(Self.statuses(version: "2.0.0"))
        let refreshCompleted = expectation(description: "repair completes while the original probe is held")
        let refresh = Task {
            await fixture.service.refresh()
            refreshCompleted.fulfill()
        }
        await waitUntil("expected repair to start a new probe while the original remains held") {
            await fixture.base.allCallCount == 2
        }
        await fixture.base.release(call: 2)
        await fulfillment(of: [refreshCompleted], timeout: 2)

        let readCompleted = expectation(description: "repaired snapshot is readable while the original probe is held")
        let read = Task {
            let statuses = await fixture.service.providerStatuses(projectURL: nil)
            readCompleted.fulfill()
            return statuses
        }
        await fulfillment(of: [readCompleted], timeout: 2)

        // The old provider ignores cancellation until its own gate opens, then answers with its old snapshot.
        await fixture.base.release()
        await refresh.value
        let repaired = await read.value
        let obsolete = await oldRead.value
        let latest = await fixture.service.providerStatuses(projectURL: nil)
        let cancelledCalls = await fixture.base.cancelledCalls
        let count = await fixture.base.allCallCount
        XCTAssertEqual(repaired[.claude]?.availability?.versionDescription, "2.0.0")
        XCTAssertEqual(obsolete[.claude]?.availability?.versionDescription, "1.0.0")
        XCTAssertEqual(latest[.claude]?.availability?.versionDescription, "2.0.0")
        XCTAssertEqual(cancelledCalls, [1])
        XCTAssertEqual(count, 2)
    }

    func testSupersededRefreshWaitsForTheCurrentProbeWithoutStartingAnother() async {
        let fixture = makeService()
        await fixture.base.setAnswer(Self.statuses(version: "1.0.0"))
        await fixture.service.warm()
        await fixture.base.hold()
        await fixture.base.setAnswer(Self.statuses(version: "2.0.0"))
        let firstCompleted = expectation(description: "first refresh observes the replacement snapshot")
        let first = Task {
            await fixture.service.refresh()
            firstCompleted.fulfill()
        }
        await waitUntil("expected the first refresh probe") { await fixture.base.allCallCount == 2 }
        await fixture.base.setAnswer(Self.statuses(version: "3.0.0"))
        let second = Task { await fixture.service.refresh() }
        await waitUntil("expected the replacement refresh probe") { await fixture.base.allCallCount == 3 }

        await fixture.base.release(call: 2)
        let earlyCompletion = await XCTWaiter.fulfillment(of: [firstCompleted], timeout: 0.2)
        XCTAssertEqual(earlyCompletion, .timedOut)

        // Release every gate before awaiting task teardown, including when a checkpoint failed.
        await fixture.base.release()
        await first.value
        await second.value
        let latest = await fixture.service.providerStatuses(projectURL: nil)
        let count = await fixture.base.allCallCount
        XCTAssertEqual(latest[.claude]?.availability?.versionDescription, "3.0.0")
        XCTAssertEqual(count, 3)
    }

    func testSupersededRefreshReusesAnAlreadyCompletedReplacement() async {
        let fixture = makeService()
        await fixture.base.hold()
        await fixture.base.setAnswer(Self.statuses(version: "1.0.0"))
        let first = Task { await fixture.service.refresh() }
        await waitUntil("expected the first cold refresh probe") { await fixture.base.allCallCount == 1 }
        await fixture.base.setAnswer(Self.statuses(version: "2.0.0"))
        let secondCompleted = expectation(description: "replacement completes before the superseded probe")
        let second = Task {
            await fixture.service.refresh()
            secondCompleted.fulfill()
        }
        await waitUntil("expected the replacement cold refresh probe") { await fixture.base.allCallCount == 2 }

        await fixture.base.release(call: 2)
        await fulfillment(of: [secondCompleted], timeout: 2)
        await fixture.base.release()
        await first.value
        await second.value

        let latest = await fixture.service.providerStatuses(projectURL: nil)
        let count = await fixture.base.allCallCount
        XCTAssertEqual(latest[.claude]?.availability?.versionDescription, "2.0.0")
        XCTAssertEqual(count, 2)
    }

    /// Distinguishable snapshots, so a test can assert which one a read served.
    private static func statuses(version: String) -> [AgentProviderID: AgentProviderStatus] {
        [
            .claude: AgentProviderStatus(
                providerId: .claude,
                definition: ClaudeProviderDefinition.definition,
                installation: .installed,
                availability: AgentProviderAvailability(
                    providerId: .claude,
                    executablePath: "/usr/local/bin/claude",
                    versionDescription: version
                ),
                setup: .ready,
                modelOptions: []
            )
        ]
    }

    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(message, file: file, line: line)
    }
}
