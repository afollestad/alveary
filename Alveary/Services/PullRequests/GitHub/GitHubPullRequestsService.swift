import Foundation

/// Fetches and mutates pull requests through the GitHub CLI so private repositories work
/// with the user's existing `gh` auth.
actor GitHubPullRequestsService: PullRequestsService {
    let diffSnapshots = PullRequestDiffJobs<PullRequestDiffSnapshot>()
    var diffShellRunner: any ShellRunner { shellRunner }
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
        do {
            return try await fetchRawDiff(id)
        } catch where Self.needsGitDiff(error) {
            return try await fetchDiffSnapshot(id).text(maxBytes: 5 * 1024 * 1024)
        }
    }

    func fetchRawDiff(_ id: PullRequestIdentifier) async throws -> String {
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
        guard let text = String(data: result.stdoutData, encoding: .utf8) else {
            throw PullRequestDiffError.invalidEncoding
        }
        return text
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
        var lastTransientFailure: ShellResult?
        while true {
            let result: ShellResult
            do {
                result = try await runGitHubCLI(
                    executable: executable,
                    args: args,
                    timeout: attemptTimeout,
                    stdoutLimitBytes: stdoutLimitBytes
                )
            } catch {
                // A retry attempt runs on a shortened timeout this function chose, so its timing
                // out says nothing the caller can act on — while the 5xx that caused the retry
                // does. Surface the failure already in hand rather than replacing it with
                // `.transport("… timed out after N seconds")`.
                guard let lastTransientFailure else {
                    throw error
                }
                return lastTransientFailure
            }
            guard !result.succeeded,
                  attempt < Self.maxTransientRetries,
                  Self.isTransientServerFailure(result) else {
                return result
            }
            lastTransientFailure = result
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

    /// The shortest attempt worth starting. A real list request measures around four seconds, so
    /// anything under this can only time out — and spending the tail of the budget on an attempt
    /// that cannot win is what replaces a nameable failure with a generic one. Two seconds was
    /// too low to prevent that: after two gateway timeouts the third attempt got about three
    /// seconds, timed out, and buried the 504 behind "timed out after 3 seconds".
    static let minimumRetryAttemptTimeout = Duration.seconds(5)

    /// How long the next retry may run, or nil to stop and return the failure already in hand.
    static func nextRetryAttemptTimeout(
        elapsed: Duration,
        nextBackoff: Duration,
        attemptTimeout: Duration,
        budget: Duration
    ) -> Duration? {
        let remaining = budget - elapsed - nextBackoff
        guard remaining >= minimumRetryAttemptTimeout else {
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
            // The body is checked before the exit code: GitHub states an over-expensive query in
            // the GraphQL `errors` array, which `makeError` cannot see because it reads stderr.
            if let classified = warnings.lazy.compactMap(Self.classify(graphQLMessage:)).first {
                throw classified
            }
            if !result.succeeded {
                throw Self.makeError(from: result)
            }
            throw PullRequestsServiceError.transport(warnings.first ?? "GraphQL query returned no data")
        }
        return (data, warnings)
    }

    /// Recognizes GitHub's refusal to *run* a query, as opposed to a query that ran and failed.
    /// It carries no HTTP status, so without this it falls through to `.transport` and surfaces
    /// GitHub's raw sentence to the user. Both null-data paths run through it — `makeError` for a
    /// message on stderr, `decodeGraphQL` for one that arrives only in the response body.
    static func classify(graphQLMessage message: String) -> PullRequestsServiceError? {
        guard message.range(of: "resource limit", options: .caseInsensitive) != nil else {
            return nil
        }
        return .queryTooExpensive
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
        if let classified = classify(graphQLMessage: message) {
            return classified
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

    /// The status is read from the digits that follow an `HTTP` marker, not from the first
    /// in-range number anywhere in the message: `gh` puts repository and pull request numbers on
    /// stderr too, and one of those landing first used to be returned as the status — which
    /// silently disabled the transient-failure retry for the 5xx that actually occurred.
    static func httpStatusCode(in message: String) -> Int? {
        var searchRange = message.startIndex..<message.endIndex
        while let marker = message.range(of: "HTTP", range: searchRange) {
            let afterMarker = message[marker.upperBound...].drop { $0 == " " || $0 == ":" }
            if let status = Int(afterMarker.prefix(while: \.isNumber)), (100...599).contains(status) {
                return status
            }
            searchRange = marker.upperBound..<message.endIndex
        }
        return nil
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
