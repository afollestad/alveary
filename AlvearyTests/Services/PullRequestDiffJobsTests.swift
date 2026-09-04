import Foundation
import Testing

@testable import Alveary

struct PullRequestDiffJobsTests {
    @Test func `a bounded wait resumes the same shared preparation`() async throws {
        let gate = MockShellRunnerGate()
        let jobs = PullRequestDiffJobs<Int>()
        let first = await jobs.start(key: "one") { await gate.wait(); return 42 }
        let second = await jobs.start(key: "one") { Issue.record("Preparation was duplicated"); return 0 }
        #expect(first == second)
        #expect(try await jobs.value(id: first, wait: .zero) == nil)
        gate.open()
        #expect(try await jobs.value(id: second) == 42)
    }

    @Test func `failed preparation can be retried with a new ticket`() async throws {
        let jobs = PullRequestDiffJobs<Int>()
        let first = await jobs.start(key: "one") { throw PullRequestDiffError.invalidComparison }
        await #expect(throws: PullRequestDiffError.self) { try await jobs.value(id: first) }
        let second = await jobs.start(key: "one") { 42 }
        #expect(first != second)
        #expect(try await jobs.value(id: second) == 42)
    }

    @Test func `preparation has its own deadline`() async throws {
        let gate = MockShellRunnerGate()
        let jobs = PullRequestDiffJobs<Int>(preparationTimeout: .zero)
        let ticket = await jobs.start(key: "one") { await gate.wait(); return 42 }
        do {
            _ = try await jobs.value(id: ticket)
            Issue.record("The preparation should time out")
        } catch PullRequestDiffError.preparationTimedOut {
            gate.open()
        }
    }

    @Test func `inactivity expires cursors and releases cached snapshots`() async throws {
        let clock = DiffJobTestClock()
        let jobs = PullRequestDiffJobs<PullRequestDiffSnapshot>(now: { clock.now })
        let ticket = await jobs.start(key: "one") { try .make(text: "") }
        var snapshot = try await jobs.value(id: ticket)
        let url = try #require(snapshot?.url)
        snapshot = nil
        clock.advance(seconds: 1_801)
        await #expect(throws: PullRequestDiffError.self) { try await jobs.value(id: ticket) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

private final class DiffJobTestClock: @unchecked Sendable {
    var now: Date { lock.withLock { date } }

    func advance(seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }

    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 0)
}
