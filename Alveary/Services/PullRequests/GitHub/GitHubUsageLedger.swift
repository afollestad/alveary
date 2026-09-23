import Foundation

/// Names the Alveary feature a GitHub request serves, so the usage ledger can say *who* spent a quota.
///
/// Task-local rather than a parameter: the requests it labels start deep below the feature that caused them, and the
/// `Task {}` inside `GitHubSharedReads` and `PullRequestDiffJobs` inherits it — so a shared in-flight read is billed to
/// the caller that started it. A request with no origin is `other`.
enum GitHubRequestOrigin {
    @TaskLocal static var current: String?
}

/// Alveary's own share of GitHub's rate-limit windows.
///
/// Every tool acting as the user — `gh`, editor extensions, AI connectors — spends one hourly budget, so an exhausted
/// quota alone cannot say whether Alveary spent it. The ledger keys usage by GitHub's own window (resource plus
/// `x-ratelimit-reset`) and keeps the account-wide `x-ratelimit-used` beside it.
///
/// It counts only requests made through `GitHubPullRequestsService`. Attachment uploads, `gh api /markdown` image
/// minting, and update checks run their own `gh` calls and are not counted.
struct GitHubUsageLedger {
    /// More Alveary requests than this against one resource in a minute is logged as a storm. Ordinary use stays
    /// far below it: a review makes a few dozen requests over several minutes.
    static let stormThreshold = 120

    struct Window: Equatable {
        let resource: String
        let resetAt: Date
        var appCost = 0
        var accountUsed: Int?
        var accountLimit: Int?
        var costByOperation: [String: Int] = [:]
        var costByOrigin: [String: Int] = [:]
    }

    let startedAt: Date
    private(set) var windows: [String: Window] = [:]
    private var recentRequests: [String: [Date]] = [:]
    private var lastStormReport: [String: Date] = [:]

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    /// One request as Alveary made it; `resource` is the fallback when GitHub's headers do not name one.
    struct Entry {
        let resource: String
        let operation: String
        let origin: String?
        let cost: Int
    }

    /// Records one request and returns a storm summary when this request crossed the threshold, at most once a
    /// minute per resource.
    mutating func record(_ entry: Entry, headers: [String: String], now: Date) -> String? {
        let resource = headers["x-ratelimit-resource"] ?? entry.resource
        if var window = window(for: resource, headers: headers, now: now) {
            window.appCost += entry.cost
            window.costByOperation[entry.operation, default: 0] += entry.cost
            window.costByOrigin[entry.origin ?? "other", default: 0] += entry.cost
            window.accountUsed = headers["x-ratelimit-used"].flatMap(Int.init) ?? window.accountUsed
            window.accountLimit = headers["x-ratelimit-limit"].flatMap(Int.init) ?? window.accountLimit
            windows[resource] = window
        }
        return recordRate(resource: resource, now: now)
    }

    /// Alveary's share of the resource's current window, or nil when the ledger has seen none.
    func usage(resource: String, now: Date) -> GitHubAppUsage? {
        guard let window = windows[resource], window.resetAt > now else {
            return nil
        }
        // GitHub windows last an hour; one that opened before launch was partly spent by an earlier process.
        let windowStart = window.resetAt.addingTimeInterval(-3600)
        return GitHubAppUsage(
            appUsed: window.appCost,
            accountUsed: window.accountUsed,
            accountLimit: window.accountLimit,
            countedSince: startedAt > windowStart ? startedAt : nil
        )
    }

    /// One line for the persisted log, naming what spent the window.
    func summary(resource: String, now: Date) -> String {
        guard let window = windows[resource], window.resetAt > now else {
            return "\(resource): no Alveary requests recorded this window"
        }
        let account = window.accountUsed.map { used in "account used \(used)/\(window.accountLimit.map(String.init) ?? "?")" }
            ?? "account usage unknown"
        let reset = window.resetAt.formatted(date: .omitted, time: .standard)
        let since = max(startedAt, window.resetAt.addingTimeInterval(-3600)).formatted(date: .omitted, time: .standard)
        return "\(resource) window resetting \(reset): \(account); Alveary used \(window.appCost) since \(since); "
            + "operations \(Self.ranked(window.costByOperation)); origins \(Self.ranked(window.costByOrigin))"
    }

    private func window(for resource: String, headers: [String: String], now: Date) -> Window? {
        guard let reset = headers["x-ratelimit-reset"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)) else {
            // No headers (a transport failure): attribute to the window already open, if any.
            return windows[resource].flatMap { $0.resetAt > now ? $0 : nil }
        }
        if let existing = windows[resource], existing.resetAt >= reset {
            // A response from the previous window landing after the next one opened must not reset its counts.
            return existing.resetAt == reset ? existing : nil
        }
        return Window(resource: resource, resetAt: reset)
    }

    private mutating func recordRate(resource: String, now: Date) -> String? {
        var requests = recentRequests[resource, default: []].filter { now.timeIntervalSince($0) < 60 }
        requests.append(now)
        recentRequests[resource] = requests
        guard requests.count > Self.stormThreshold,
              lastStormReport[resource].map({ now.timeIntervalSince($0) >= 60 }) ?? true else {
            return nil
        }
        lastStormReport[resource] = now
        return "Alveary made \(requests.count) \(resource) requests in the last minute; " + summary(resource: resource, now: now)
    }

    private static func ranked(_ costs: [String: Int]) -> String {
        costs.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

/// Alveary's share of the window a rate limit applies to, carried on `GitHubRateLimit` so the text that reports
/// the limit can say whether Alveary spent it.
struct GitHubAppUsage: Codable, Equatable, Sendable {
    let appUsed: Int
    let accountUsed: Int?
    let accountLimit: Int?
    /// Set when the ledger started after the window opened, so earlier spending may be Alveary's too.
    let countedSince: Date?
}
