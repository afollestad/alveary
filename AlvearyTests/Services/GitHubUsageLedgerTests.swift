import Foundation
import Testing

@testable import Alveary

struct GitHubUsageLedgerTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    @Test
    func `usage follows GitHub's window and keeps the account total beside Alveary's share`() {
        var ledger = GitHubUsageLedger(startedAt: start.addingTimeInterval(-7200))
        let reset = start.addingTimeInterval(1800)
        _ = ledger.record(entry(operation: "detail", origin: "tool:get_pr", cost: 1), headers: headers(used: 40, reset: reset), now: start)
        _ = ledger.record(entry(operation: "list", origin: nil, cost: 2), headers: headers(used: 4990, reset: reset), now: start)

        let window = ledger.windows["graphql"]
        #expect(window?.appCost == 3)
        #expect(window?.costByOperation == ["detail": 1, "list": 2])
        #expect(window?.costByOrigin == ["tool:get_pr": 1, "other": 2])
        #expect(ledger.usage(resource: "graphql", now: start) == GitHubAppUsage(
            appUsed: 3, accountUsed: 4990, accountLimit: 5000, countedSince: nil
        ))
    }

    @Test
    func `a new reset opens a fresh window and a late response from the old one cannot reset it`() {
        var ledger = GitHubUsageLedger(startedAt: start.addingTimeInterval(-7200))
        let oldReset = start.addingTimeInterval(60)
        let newReset = start.addingTimeInterval(3660)
        _ = ledger.record(entry(cost: 5), headers: headers(used: 5000, reset: oldReset), now: start)
        _ = ledger.record(entry(cost: 1), headers: headers(used: 1, reset: newReset), now: start.addingTimeInterval(61))
        _ = ledger.record(entry(cost: 7), headers: headers(used: 5000, reset: oldReset), now: start.addingTimeInterval(62))

        #expect(ledger.windows["graphql"]?.resetAt == newReset)
        #expect(ledger.windows["graphql"]?.appCost == 1)
        #expect(ledger.usage(resource: "graphql", now: start.addingTimeInterval(62))?.accountUsed == 1)
    }

    @Test
    func `a window that opened before launch reports where counting began`() {
        var ledger = GitHubUsageLedger(startedAt: start)
        _ = ledger.record(entry(cost: 1), headers: headers(used: 100, reset: start.addingTimeInterval(600)), now: start)

        #expect(ledger.usage(resource: "graphql", now: start)?.countedSince == start)
        #expect(ledger.usage(resource: "graphql", now: start.addingTimeInterval(601)) == nil)
    }

    @Test
    func `a storm is reported once a minute with its top origins`() {
        var ledger = GitHubUsageLedger(startedAt: start)
        let reset = start.addingTimeInterval(3600)
        var reports: [String] = []
        for index in 0...GitHubUsageLedger.stormThreshold {
            let now = start.addingTimeInterval(Double(index) * 0.1)
            if let report = ledger.record(entry(origin: "team-review", cost: 1), headers: headers(used: index, reset: reset), now: now) {
                reports.append(report)
            }
        }
        let quietFollowUp = ledger.record(entry(cost: 1), headers: headers(used: 200, reset: reset), now: start.addingTimeInterval(30))

        #expect(reports.count == 1)
        #expect(reports.first?.contains("team-review=121") == true)
        #expect(quietFollowUp == nil)
    }

    @Test
    func `limit text says how much of the shared budget Alveary spent`() {
        let retryAt = Date(timeIntervalSince1970: 20_000)
        var limit = GitHubRateLimit(resource: "graphql", isSecondary: false, retryAt: retryAt)
        #expect(!limit.waitingMessage.contains("Alveary used"))

        limit.appUsage = GitHubAppUsage(appUsed: 212, accountUsed: 5000, accountLimit: 5000, countedSince: nil)
        #expect(limit.waitingMessage.hasSuffix("Alveary used 212 of the 5,000 points spent this hour."))
        #expect(limit.message.hasSuffix("Alveary used 212 of the 5,000 points spent this hour."))
    }

    @Test
    func `service records origins through shared reads and attaches usage to the limit it reports`() async throws {
        let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: """
        HTTP/2.0 200 OK
        X-RateLimit-Remaining: 1
        X-RateLimit-Used: 4999
        X-RateLimit-Limit: 5000
        X-RateLimit-Resource: graphql
        X-RateLimit-Reset: \(reset)

        \(PullRequestsServiceFixtures.detail)
        """)))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: """
        HTTP/2.0 200 OK
        X-RateLimit-Remaining: 0
        X-RateLimit-Used: 5000
        X-RateLimit-Limit: 5000
        X-RateLimit-Resource: graphql
        X-RateLimit-Reset: \(reset)

        {"data":null,"errors":[{"type":"RATE_LIMIT","message":"API rate limit already exceeded"}]}
        """, exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)
        let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

        _ = try await GitHubRequestOrigin.$current.withValue("tool:get_pr") {
            try await service.fetchReviewContext(id)
        }
        await #expect {
            try await service.fetchRevision(id)
        } throws: { error in
            guard case PullRequestsServiceError.rateLimit(let limit)? = error as? PullRequestsServiceError else { return false }
            // The refused request spent nothing, so Alveary's share stays at the one read that landed.
            return limit.appUsage == GitHubAppUsage(appUsed: 1, accountUsed: 5000, accountLimit: 5000, countedSince: limit.appUsage?.countedSince)
        }
        let window = await service.usageLedger.windows["graphql"]
        #expect(window?.costByOrigin == ["tool:get_pr": 1, "other": 0])
        #expect(window?.costByOperation["revision"] == 0)
    }

    private func entry(operation: String = "detail", origin: String? = "tool:get_pr", cost: Int) -> GitHubUsageLedger.Entry {
        GitHubUsageLedger.Entry(resource: "graphql", operation: operation, origin: origin, cost: cost)
    }

    private func headers(used: Int, reset: Date) -> [String: String] {
        [
            "x-ratelimit-used": "\(used)",
            "x-ratelimit-limit": "5000",
            "x-ratelimit-resource": "graphql",
            "x-ratelimit-reset": "\(Int(reset.timeIntervalSince1970))"
        ]
    }
}
