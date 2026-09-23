import Foundation
import Testing

@testable import Alveary

struct GitHubQuotaTests {
    @Test
    func `new diff comparisons cannot inherit older in flight diff bytes`() async throws {
        let gate = MockShellRunnerGate()
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "old diff")))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "new diff")))
        await shell.setGate(gate)
        let service = makeGitHubPullRequestsService(shell: shell)
        let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let old = Task { try await service.fetchRawDiff(id) }
        defer { gate.open(); old.cancel() }
        try await waitUntil { await shell.invocations.count == 1 }
        let new = Task { try await service.fetchRawDiff(id) }
        defer { new.cancel() }
        try await waitUntil { await shell.invocations.count == 2 }
        gate.open()
        #expect(try await old.value == "old diff")
        #expect(try await new.value == "new diff")
    }

    @Test
    func `six different pull requests remain fully concurrent`() async throws {
        let gate = MockShellRunnerGate()
        let shell = MockShellRunner(defaultResponse: .success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        await shell.setGate(gate)
        let service = makeGitHubPullRequestsService(shell: shell)
        let tasks = (1...6).map { number in
            Task { try await service.fetchReviewContext(PullRequestIdentifier(owner: "octo", repo: "alpha", number: number)) }
        }
        defer { gate.open(); tasks.forEach { $0.cancel() } }
        try await waitUntil { await shell.invocations.count == 6 }
        gate.open()
        for task in tasks { _ = try await task.value }
    }

    @Test
    func `overlapping reads share work but later reads and revision checks stay fresh`() async throws {
        let gate = MockShellRunnerGate()
        let shell = MockShellRunner(defaultResponse: .success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        await shell.setGate(gate)
        let service = makeGitHubPullRequestsService(shell: shell)
        let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let first = Task { try await service.fetchReviewContext(id) }
        let second = Task { try await service.fetchReviewContext(id) }
        defer { gate.open(); first.cancel(); second.cancel() }
        try await waitUntil { await service.sharedReads.waiterCount == 2 }
        #expect(await shell.invocations.count <= 1)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        gate.open()
        _ = try await second.value
        _ = try await service.fetchReviewContext(id)
        async let revision1 = service.fetchRevision(id)
        async let revision2 = service.fetchRevision(id)
        _ = try await (revision1, revision2)
        #expect(await shell.invocations.count == 4)
    }

    @Test
    func `review metadata excludes expensive connections and revision reads exclude descriptions`() async throws {
        let shell = MockShellRunner(defaultResponse: .success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        let service = makeGitHubPullRequestsService(shell: shell)
        let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let context = try await service.fetchReviewContext(id)
        _ = try await service.fetchRevision(id)
        #expect(context.title == "Improve parser")
        let calls = await shell.invocations
        for call in calls {
            let query = try #require(call.args.first { $0.hasPrefix("query=") })
            #expect(!query.contains("reviewThreads"))
            #expect(!query.contains("statusCheckRollup"))
            #expect(!query.contains("reactionGroups"))
            #expect(call.args.contains("--include"))
        }
        #expect(calls[1].args.allSatisfy { !$0.contains("title body") })
    }

    @Test(arguments: ["429 Too Many Requests", "403 Forbidden", "200 OK"])
    func `rate limit response pauses subsequent reads without spawning gh`(status: String) async throws {
        let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let body = """
        HTTP/2.0 \(status)
        X-RateLimit-Remaining: 0
        X-RateLimit-Resource: graphql
        X-RateLimit-Reset: \(reset)

        {"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}
        """
        let shell = MockShellRunner(defaultResponse: .success(pullRequestsShellResult(stdout: body, exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)
        let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        for attempt in 0..<2 {
            do {
                _ = try await service.fetchReviewContext(id)
                Issue.record("Expected a quota error")
            } catch PullRequestsServiceError.rateLimit(let limit) {
                #expect(limit.resource == "graphql")
                #expect(limit.retryAt == Date(timeIntervalSince1970: Double(reset)))
                #expect(limit.isResponse == (attempt == 0))
            }
        }
        #expect(await shell.invocations.count == 1)
    }

    @Test
    func `primary cooldown is scoped and secondary recovery permits one probe`() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var quota = GitHubQuotaState()
        let primary = response(headers: "x-ratelimit-remaining: 0\nx-ratelimit-resource: graphql\nx-ratelimit-reset: 1100")
        _ = quota.finish(response: primary, resource: "graphql", permits: [:], now: now)
        #expect(try quota.begin(resource: "core", now: now).isEmpty)
        #expect(throws: PullRequestsServiceError.self) { try quota.begin(resource: "graphql", now: now) }
        let secondary = response(headers: "retry-after: 60", message: "secondary rate limit exceeded")
        _ = quota.finish(response: secondary, resource: "core", permits: [:], now: now)
        #expect(throws: PullRequestsServiceError.self) { try quota.begin(resource: "core", now: now) }
        let later = now.addingTimeInterval(120)
        let permit = try quota.begin(resource: "graphql", now: later)
        #expect(throws: PullRequestsServiceError.self) { try quota.begin(resource: "core", now: later) }
        let success = GitHubAPIResponse(pullRequestsShellResult(stdout: "{}"))
        _ = quota.finish(response: success, resource: "graphql", permits: permit, now: later)
        #expect(try quota.begin(resource: "graphql", now: later).isEmpty)
        #expect(try quota.begin(resource: "core", now: later).isEmpty)
    }

    @Test(arguments: [false, true])
    func `concurrent responses cannot shorten a known cooldown`(secondary: Bool) throws {
        let now = Date(timeIntervalSince1970: 1000)
        var quota = GitHubQuotaState()
        let headers = secondary ? "retry-after: 600"
            : "x-ratelimit-remaining: 0\nx-ratelimit-resource: graphql\nx-ratelimit-reset: 1600"
        _ = quota.finish(response: response(headers: headers), resource: "graphql", permits: [:], now: now)
        let shorter: GitHubAPIResponse
        if secondary {
            shorter = response(headers: "retry-after: 60")
        } else {
            shorter = GitHubAPIResponse(pullRequestsShellResult(stdout:
                "HTTP/2.0 200 OK\nx-ratelimit-remaining: 0\nx-ratelimit-resource: graphql\nx-ratelimit-reset: 1100\n\n{}"))
        }
        _ = quota.finish(response: shorter, resource: secondary ? "core" : "graphql", permits: [:], now: now.addingTimeInterval(1))
        #expect(throws: PullRequestsServiceError.self) { try quota.begin(resource: "graphql", now: now.addingTimeInterval(101)) }
        #expect(!(try quota.begin(resource: "graphql", now: now.addingTimeInterval(600))).isEmpty)
    }

    @Test(arguments: [false, true])
    func `six restored waits admit only one recovery request`(secondary: Bool) throws {
        let now = Date(timeIntervalSince1970: 1000)
        let limit = GitHubRateLimit(resource: "graphql", isSecondary: secondary, retryAt: now)
        var quota = GitHubQuotaState()
        for _ in 0..<6 { quota.restore(limit) }
        let permit = try quota.begin(resource: "graphql", now: now)
        for _ in 0..<5 {
            quota.restore(limit)
            #expect(throws: PullRequestsServiceError.self) {
                try quota.begin(resource: secondary ? "core" : "graphql", now: now)
            }
        }
        _ = quota.finish(response: GitHubAPIResponse(pullRequestsShellResult(stdout: "{}")),
                         resource: "graphql", permits: permit, now: now)
        for _ in 0..<6 { #expect(try quota.begin(resource: "graphql", now: now).isEmpty) }
    }

    @Test
    func `new cooldown observations cannot bypass an active probe or be cleared by it`() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var quota = GitHubQuotaState()
        quota.restore(GitHubRateLimit(resource: "graphql", isSecondary: true, retryAt: now))
        let original = try quota.begin(resource: "graphql", now: now)
        _ = quota.finish(response: response(headers: "retry-after: 0"), resource: "core", permits: [:], now: now)
        #expect(throws: PullRequestsServiceError.self) { try quota.begin(resource: "core", now: now) }
        _ = quota.finish(response: nil, resource: "graphql", permits: original, now: now)
        let replacement = try quota.begin(resource: "core", now: now)
        let success = GitHubAPIResponse(pullRequestsShellResult(stdout: "{}"))
        _ = quota.finish(response: success, resource: "graphql", permits: original, now: now)
        #expect(throws: PullRequestsServiceError.self) { try quota.begin(resource: "graphql", now: now) }
        _ = quota.finish(response: success, resource: "core", permits: replacement, now: now)
        #expect(try quota.begin(resource: "graphql", now: now).isEmpty)
    }

    @Test
    func `secondary backoff is shared across resources and resets after recovery`() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let failure = response(headers: "", message: "secondary rate limit exceeded")
        var quota = GitHubQuotaState()
        _ = quota.finish(response: failure, resource: "graphql", permits: [:], now: now)
        let second = quota.finish(response: failure, resource: "core", permits: [:], now: now)
        #expect(second?.retryAt == now.addingTimeInterval(120))
        let later = now.addingTimeInterval(120)
        let permit = try quota.begin(resource: "core", now: later)
        _ = quota.finish(response: GitHubAPIResponse(pullRequestsShellResult(stdout: "{}")),
                         resource: "core", permits: permit, now: later)
        let next = quota.finish(response: failure, resource: "graphql", permits: [:], now: later)
        #expect(next?.retryAt == later.addingTimeInterval(60))
    }

    @Test
    func `missing retry headers back off while server deadlines take precedence`() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let missing = response(headers: "")
        #expect(missing.cooldown(resource: "graphql", now: now, consecutiveFailures: 1)?.retryAt == now.addingTimeInterval(60))
        #expect(missing.cooldown(resource: "graphql", now: now, consecutiveFailures: 3)?.retryAt == now.addingTimeInterval(240))
        let explicit = response(headers: "retry-after: 120\nx-ratelimit-remaining: 0\nx-ratelimit-reset: 1300")
        #expect(explicit.cooldown(resource: "graphql", now: now, consecutiveFailures: 5)?.retryAt == now.addingTimeInterval(300))
    }

    @Test(arguments: ["RATE_LIMITED", "RATE_LIMIT"])
    func `either GraphQL rate limit error type is a limit without relying on its wording`(type: String) {
        let body = "{\"data\":null,\"errors\":[{\"type\":\"\(type)\",\"message\":\"Slow down.\"}]}"
        #expect(GitHubAPIResponse(pullRequestsShellResult(stdout: body, exitCode: 1)).isRateLimited)
    }

    @Test
    func `headers leave diff bytes intact and provide query cost`() {
        let diff = "diff --git a/File.swift b/File.swift\n+added\n"
        let response = GitHubAPIResponse(pullRequestsShellResult(stdout: "HTTP/2.0 200 OK\r\nX-RateLimit-Remaining: 42\r\n\r\n" + diff))
        #expect(response.result.stdoutData == Data(diff.utf8))
        #expect(response.headers["x-ratelimit-remaining"] == "42")
        let graphql = GitHubAPIResponse(pullRequestsShellResult(stdout: "{\"data\":{\"rateLimit\":{\"cost\":7}}}"))
        #expect(graphql.queryCost == 7)
    }

    private func response(headers: String, message: String = "API rate limit exceeded") -> GitHubAPIResponse {
        GitHubAPIResponse(pullRequestsShellResult(stdout: "HTTP/2.0 403 Forbidden\n\(headers)\n\n{\"message\":\"\(message)\"}", exitCode: 1))
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while !(await condition()) {
            guard clock.now < deadline else { throw CancellationError() }
            await Task.yield()
        }
    }
}
