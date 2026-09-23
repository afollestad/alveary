import Foundation
import OSLog

/// Observes quota on existing requests; no polling or concurrency cap is imposed on healthy traffic. Every response
/// also feeds `usageLedger`, so a limit can report how much of the shared budget Alveary spent.
extension GitHubPullRequestsService {
    func restoreRateLimits(_ limits: [GitHubRateLimit]) {
        for limit in limits { quotaState.restore(limit) }
    }

    // swiftlint:disable:next function_parameter_count
    func executeGitHubRequest(
        executable: String, args: [String], directory: String?, timeout: Duration,
        stdoutLimitBytes: Int?, standardInput: ShellStandardInput, readOnly: Bool
    ) async throws -> ShellResult {
        let resource = args.prefix(2) == ["api", "graphql"] ? "graphql" : "core"
        let permits: [String: UUID]
        do {
            permits = try readOnly ? quotaState.begin(resource: resource, now: .now) : [:]
        } catch PullRequestsServiceError.rateLimit(var limit) {
            limit.appUsage = usageLedger.usage(resource: limit.resource, now: .now)
            throw PullRequestsServiceError.rateLimit(limit)
        }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let includedArgs = args.first == "api" && !args.contains("--include") ? args + ["--include"] : args
            let raw = try await shellRunner.run(
                executable: executable, args: includedArgs, in: directory, timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes.map { $0 + 64 * 1024 }, stderrLimitBytes: 64 * 1024,
                standardInput: standardInput
            )
            let response = GitHubAPIResponse(raw)
            let finished = quotaState.finish(response: response, resource: resource, permits: permits, now: .now)
            let operation = Self.requestOperation(args)
            recordUsage(response: response, resource: resource, operation: operation)
            Self.logRequest(operation: operation, response: response, duration: clock.now - start)
            if var limit = finished {
                limit.appUsage = usageLedger.usage(resource: limit.resource, now: .now)
                let summary = usageLedger.summary(resource: limit.resource, now: .now)
                Self.logger.error("GitHub limited requests. \(summary, privacy: .public)")
                throw PullRequestsServiceError.rateLimit(limit)
            }
            guard stdoutLimitBytes.map({ response.result.stdoutData.count <= $0 }) ?? true else {
                throw PullRequestsServiceError.responseTooLarge
            }
            return response.result
        } catch {
            _ = quotaState.finish(response: nil, resource: resource, permits: permits, now: .now)
            throw error
        }
    }

    private static let logger = Logger(subsystem: "com.afollestad.alveary", category: "GitHubQuota")

    /// Mutations included: they spend the same budget even though no cooldown gates them.
    private func recordUsage(response: GitHubAPIResponse, resource: String, operation: String) {
        let entry = GitHubUsageLedger.Entry(
            resource: resource,
            operation: operation,
            origin: GitHubRequestOrigin.current,
            // A refused request spends nothing, but still counts toward the storm rate.
            cost: response.isRateLimited ? 0 : response.queryCost ?? 1
        )
        let storm = usageLedger.record(entry, headers: response.headers, now: .now)
        if let storm {
            Self.logger.error("\(storm, privacy: .public)")
        }
    }

    private static func logRequest(operation: String, response: GitHubAPIResponse, duration: Duration) {
        let remaining = response.headers["x-ratelimit-remaining"] ?? "unknown"
        let reset = response.headers["x-ratelimit-reset"] ?? "unknown"
        let resource = response.headers["x-ratelimit-resource"] ?? "unknown"
        let cost = response.queryCost.map(String.init) ?? "unknown"
        let origin = GitHubRequestOrigin.current ?? "other"
        let metrics = "\(operation) origin=\(origin) duration=\(duration) resource=\(resource) remaining=\(remaining) "
            + "reset=\(reset) cost=\(cost)"
        logger.info("\(metrics, privacy: .public)")
    }

    private static func requestOperation(_ args: [String]) -> String {
        guard args.prefix(2) == ["api", "graphql"] else {
            if args.contains("Accept: application/vnd.github.diff") { return "diff" }
            return args.contains("--jq") ? "comparison" : "rest mutation"
        }
        let query = args.first { $0.hasPrefix("query=") } ?? ""
        if query.contains("query=mutation") { return "graphql mutation" }
        if query.contains("search(type:") { return "list" }
        if query.contains("statusCheckRollup") { return "detail" }
        if query.contains("changedFiles author") { return "review context" }
        if query.contains("pageInfo") { return "review feedback" }
        if query.contains("baseRefOid headRefOid") { return "revision" }
        return "graphql"
    }
}
