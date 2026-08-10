import Foundation

/// Fetches and mutates pull requests through the GitHub CLI so private repositories work
/// with the user's existing `gh` auth.
actor GitHubPullRequestsService: PullRequestsService {
    private static let maxTransientRetries = 2

    /// What one list or detail attempt may take, and what the whole call may take including
    /// retries and their backoff. Both sit under the 30 seconds the host-tool bridge allows a
    /// tool call, so a wedged `gh` fails as its own named timeout with room left to decode and
    /// merge — at 30 seconds per attempt the bridge always won the race and replaced every
    /// cause with a generic "Host tool call timed out."
    private static let readAttemptTimeout = Duration.seconds(20)
    private static let readRetryBudget = Duration.seconds(25)

    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving
    private let decoder: JSONDecoder
    private let transientRetryDelay: Duration

    init(
        shellRunner: any ShellRunner = DefaultShellRunner(),
        executableResolver: (any ExecutablePathResolving)? = nil,
        transientRetryDelay: Duration = .milliseconds(400)
    ) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver ?? DefaultExecutablePathResolver(shell: shellRunner)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.transientRetryDelay = transientRetryDelay
    }

    func listInvolvedPullRequests(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?,
        options: PullRequestListOptions
    ) async throws -> PullRequestListResult {
        let ordered = Self.orderedBuckets(buckets)
        guard !ordered.isEmpty else {
            return PullRequestListResult(summariesByBucket: [:], warnings: [])
        }
        let ghExecutable = try await resolveGitHubCLI()
        guard ordered.count > 1 else {
            return try await listBucket(ordered[0], status: status, options: options, ghExecutable: ghExecutable)
        }
        let outcomes = await fetchBucketsConcurrently(
            ordered,
            status: status,
            options: options,
            ghExecutable: ghExecutable
        )
        return try Self.mergeBucketOutcomes(outcomes)
    }

    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: ghExecutable,
            args: Self.detailArgs(for: id),
            timeout: Self.readAttemptTimeout,
            stdoutLimitBytes: 8 * 1024 * 1024,
            retryBudget: Self.readRetryBudget
        )
        let decoded = try decodeGraphQL(DetailGraphQLData.self, from: result)
        guard let node = decoded.data.repository?.pullRequest else {
            throw PullRequestsServiceError.transport(decoded.warnings.first ?? "Pull request not found")
        }
        return Self.makeDetail(id: id, node: node, viewer: decoded.data.viewer)
    }

    func fetchDiff(_ id: PullRequestIdentifier) async throws -> String {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: ghExecutable,
            args: ["pr", "diff", String(id.number), "--repo", id.nameWithOwner],
            timeout: .seconds(60),
            stdoutLimitBytes: 5 * 1024 * 1024
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        guard !result.stdoutWasTruncated else {
            throw PullRequestsServiceError.responseTooLarge
        }
        return result.stdout
    }

    /// One `gh` invocation per bucket, in parallel. GitHub runs a batched request's aliased
    /// searches *serially*, so three buckets in one request cost about three searches while three
    /// requests cost about one — which is what keeps a multi-bucket call inside the host-tool
    /// bridge's budget. Legs land as `Result`s so one refusing bucket degrades the answer instead
    /// of failing it; `mergeBucketOutcomes` owns that contract.
    private func fetchBucketsConcurrently(
        _ buckets: [PullRequestInvolvementBucket],
        status: PullRequestStatus?,
        options: PullRequestListOptions,
        ghExecutable: String
    ) async -> [PullRequestInvolvementBucket: PullRequestBucketOutcome] {
        await withTaskGroup(of: (PullRequestInvolvementBucket, PullRequestBucketOutcome).self) { group in
            for bucket in buckets {
                group.addTask {
                    do {
                        let result = try await self.listBucket(
                            bucket,
                            status: status,
                            options: options,
                            ghExecutable: ghExecutable
                        )
                        return (bucket, .success(result))
                    } catch let error as PullRequestsServiceError {
                        return (bucket, .failure(error))
                    } catch {
                        return (bucket, .failure(.transport(error.localizedDescription)))
                    }
                }
            }
            var outcomes: [PullRequestInvolvementBucket: PullRequestBucketOutcome] = [:]
            for await (bucket, outcome) in group {
                outcomes[bucket] = outcome
            }
            return outcomes
        }
    }

    /// One bucket's page. `options` is passed through whole rather than narrowed to this bucket's
    /// cursor: `listArgs` reads only the entries whose bucket it is building an argument for, so a
    /// sibling's cursor cannot reach this leg's request.
    private func listBucket(
        _ bucket: PullRequestInvolvementBucket,
        status: PullRequestStatus?,
        options: PullRequestListOptions,
        ghExecutable: String
    ) async throws -> PullRequestListResult {
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: ghExecutable,
            args: Self.listArgs(buckets: [bucket], status: status, options: options),
            timeout: Self.readAttemptTimeout,
            stdoutLimitBytes: 4 * 1024 * 1024,
            retryBudget: Self.readRetryBudget
        )
        let decoded = try decodeGraphQL(ListGraphQLData.self, from: result)
        return Self.makeListResult(data: decoded.data, warnings: decoded.warnings, buckets: [bucket])
    }
}

// Shared shell plumbing for the reads above and the mutations in
// `GitHubPullRequestsService+Mutations.swift`.
extension GitHubPullRequestsService {
    func resolveGitHubCLI() async throws -> String {
        guard let path = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw PullRequestsServiceError.ghNotInstalled
        }
        return path
    }

    /// Read-only calls retry transient GitHub 5xx responses (the GraphQL search
    /// endpoint 502s intermittently). Mutations such as review submission must not
    /// use this — they are not idempotent.
    ///
    /// `retryBudget` bounds the attempts *and their backoff* together; nil lets them run as long
    /// as `timeout` times the attempt count allows. A caller working under someone else's deadline
    /// passes one so its own failure arrives first and names the cause.
    func runGitHubCLIRetryingTransientFailures(
        executable: String,
        args: [String],
        timeout: Duration,
        stdoutLimitBytes: Int? = 64 * 1024,
        retryBudget: Duration? = nil
    ) async throws -> ShellResult {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var attempt = 0
        var attemptTimeout = timeout
        while true {
            let result = try await runGitHubCLI(
                executable: executable,
                args: args,
                timeout: attemptTimeout,
                stdoutLimitBytes: stdoutLimitBytes
            )
            guard !result.succeeded,
                  attempt < Self.maxTransientRetries,
                  Self.isTransientServerFailure(result) else {
                return result
            }
            attempt += 1
            let backoff = transientRetryDelay * attempt
            if let retryBudget {
                guard let nextTimeout = Self.nextRetryAttemptTimeout(
                    elapsed: clock.now - startedAt,
                    nextBackoff: backoff,
                    attemptTimeout: timeout,
                    budget: retryBudget
                ) else {
                    return result
                }
                attemptTimeout = nextTimeout
            }
            do {
                try await Task.sleep(for: backoff)
            } catch {
                // Cancelled mid-backoff: surface the last failure instead of retrying.
                return result
            }
        }
    }

    /// How long the next retry may run, or nil to stop and return the failure already in hand.
    /// Under two seconds an attempt can only time out, and doing that *past* the budget is the
    /// case this exists to prevent — a caller's own deadline would fire first and replace a
    /// nameable failure with a generic one.
    static func nextRetryAttemptTimeout(
        elapsed: Duration,
        nextBackoff: Duration,
        attemptTimeout: Duration,
        budget: Duration
    ) -> Duration? {
        let remaining = budget - elapsed - nextBackoff
        guard remaining >= .seconds(2) else {
            return nil
        }
        return min(attemptTimeout, remaining)
    }

    static func isTransientServerFailure(_ result: ShellResult) -> Bool {
        guard case .requestFailed(let statusCode) = makeError(from: result) else {
            return false
        }
        return (502...504).contains(statusCode)
    }

    /// `directory` is nil for the `gh api` calls, which name their repository
    /// explicitly; `pr create` resolves the repository from the working
    /// directory instead, so it is the one caller that passes it.
    ///
    /// Nothing here feeds `gh` on stdin, so the default is `.nullDevice`: inheriting it lets a
    /// credential or keychain prompt block the child until the caller's timeout, turning a
    /// one-keystroke re-auth into an unexplained hang.
    func runGitHubCLI(
        executable: String,
        args: [String],
        in directory: String? = nil,
        timeout: Duration,
        stdoutLimitBytes: Int? = 64 * 1024,
        standardInput: ShellStandardInput = .nullDevice
    ) async throws -> ShellResult {
        do {
            return try await shellRunner.run(
                executable: executable,
                args: args,
                in: directory,
                timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes,
                stderrLimitBytes: 64 * 1024,
                standardInput: standardInput
            )
        } catch let error as PullRequestsServiceError {
            throw error
        } catch {
            throw PullRequestsServiceError.transport(error.localizedDescription)
        }
    }

    /// Decodes a GraphQL envelope, tolerating partial results: SAML-protected organizations
    /// make `gh` exit non-zero while still returning valid `data` plus per-node `errors`.
    func decodeGraphQL<DataShape: Decodable>(
        _ type: DataShape.Type,
        from result: ShellResult
    ) throws -> (data: DataShape, warnings: [String]) {
        guard !result.stdoutWasTruncated else {
            throw PullRequestsServiceError.responseTooLarge
        }
        let response: GraphQLResponse<DataShape>
        do {
            response = try decoder.decode(GraphQLResponse<DataShape>.self, from: result.stdoutData)
        } catch {
            if !result.succeeded {
                throw Self.makeError(from: result)
            }
            throw PullRequestsServiceError.decodingFailed(error.localizedDescription)
        }
        let warnings = Self.uniqueMessages(from: response.errors)
        guard let data = response.data else {
            if !result.succeeded {
                throw Self.makeError(from: result)
            }
            throw PullRequestsServiceError.transport(warnings.first ?? "GraphQL query returned no data")
        }
        return (data, warnings)
    }

    static func makeError(from result: ShellResult) -> PullRequestsServiceError {
        let message = failureMessage(from: result)
        if message.contains("HTTP 401") {
            return .notAuthenticated
        }
        if message.range(of: "gh auth login", options: .caseInsensitive) != nil
            || message.range(of: "not logged in", options: .caseInsensitive) != nil {
            return .notAuthenticated
        }
        if message.contains("HTTP 403"),
           message.range(of: "rate limit", options: .caseInsensitive) != nil {
            return .rateLimited
        }
        if let statusCode = httpStatusCode(in: message) {
            return .requestFailed(statusCode: statusCode)
        }
        if result.exitCode == 127 {
            return .ghNotInstalled
        }
        return .transport(message.isEmpty ? "GitHub CLI exited with \(result.exitCode)." : message)
    }

    static func failureMessage(from result: ShellResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func httpStatusCode(in message: String) -> Int? {
        guard message.contains("HTTP") else {
            return nil
        }
        return message
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .first { (100...599).contains($0) }
    }

    static func uniqueMessages(from errors: [GraphQLErrorEntry]?) -> [String] {
        guard let errors else {
            return []
        }
        var seen = Set<String>()
        return errors.compactMap { entry in
            guard let message = entry.message, !message.isEmpty, seen.insert(message).inserted else {
                return nil
            }
            return message
        }
    }
}
