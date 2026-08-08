import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// The cache in front of provider discovery. Its whole job is to keep thread creation off the
/// subprocess fan-out, without ever answering a project-scoped or post-install read from memory.
final class AgentProviderDiscoveryCacheTests: XCTestCase {
    /// Counts probes and can be held open, so a test can prove coalescing rather than infer it.
    private actor ProbeCountingDiscovery: AgentProviderDiscoveryService {
        private(set) var allCallCount = 0
        private(set) var lastProjectURLs: [URL?] = []
        private var gate: CheckedContinuation<Void, Never>?
        private var isHeld = false

        func hold() {
            isHeld = true
        }

        func release() {
            isHeld = false
            gate?.resume()
            gate = nil
        }

        func providerStatuses(projectURL: URL?) async -> [AgentProviderID: AgentProviderStatus] {
            allCallCount += 1
            lastProjectURLs.append(projectURL)
            if isHeld {
                await withCheckedContinuation { continuation in
                    gate = continuation
                }
            }
            return [:]
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

    func testAReadPastTheWindowProbesAgain() async {
        let fixture = makeService()

        _ = await fixture.service.providerStatuses(projectURL: nil)
        fixture.clock.advance(61)
        _ = await fixture.service.providerStatuses(projectURL: nil)

        let count = await fixture.base.allCallCount
        XCTAssertEqual(count, 2)
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
}
