import Foundation

/// Requests stay fully parallel unless GitHub has reported an exhausted quota or secondary limit.
struct GitHubQuotaState {
    /// Restored waits seed recovery coordination before any resumed request starts.
    mutating func restore(_ limit: GitHubRateLimit) {
        let key = limit.isSecondary ? "*" : limit.resource
        guard cooldowns[key].map({ $0.limit.retryAt < limit.retryAt }) ?? true else { return }
        cooldowns[key] = Entry(id: UUID(), limit: limit)
    }

    mutating func begin(resource: String, now: Date) throws -> [String: UUID] {
        var permits: [String: UUID] = [:]
        for key in ["*", resource] {
            guard let entry = cooldowns[key] else { continue }
            if entry.limit.retryAt > now || probes[key] != nil {
                throw PullRequestsServiceError.rateLimit(GitHubRateLimit(
                    resource: entry.limit.resource, isSecondary: entry.limit.isSecondary,
                    retryAt: max(entry.limit.retryAt, now.addingTimeInterval(1)), isResponse: false
                ))
            }
            permits[key] = entry.id
        }
        probes.merge(permits) { _, new in new }
        return permits
    }

    mutating func finish(
        response: GitHubAPIResponse?, resource: String, permits: [String: UUID], now: Date
    ) -> GitHubRateLimit? {
        for (key, id) in permits where probes[key] == id { probes[key] = nil }
        guard let response else { return nil }
        let failureKey = response.isSecondary || response.headers["x-ratelimit-remaining"] != "0"
            ? "*" : response.headers["x-ratelimit-resource"] ?? resource
        if response.isRateLimited { failures[failureKey, default: 0] += 1 }
        if let limit = response.cooldown(resource: resource, now: now, consecutiveFailures: failures[failureKey, default: 0]) {
            let key = limit.isSecondary ? "*" : limit.resource
            let merged = GitHubRateLimit(resource: limit.resource, isSecondary: limit.isSecondary,
                                         retryAt: max(limit.retryAt, cooldowns[key]?.limit.retryAt ?? limit.retryAt))
            cooldowns[key] = Entry(id: UUID(), limit: merged)
            return response.isRateLimited ? merged : nil
        } else if response.result.succeeded {
            for (key, id) in permits where cooldowns[key]?.id == id {
                cooldowns[key] = nil
                failures[key] = nil
            }
            if cooldowns[resource] == nil { failures[resource] = nil }
        }
        return nil
    }

    private struct Entry {
        let id: UUID
        let limit: GitHubRateLimit
    }

    private var cooldowns: [String: Entry] = [:]
    private var failures: [String: Int] = [:]
    /// A later response can replace a cooldown while its earlier recovery request is still running.
    private var probes: [String: UUID] = [:]
}
