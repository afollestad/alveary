import Foundation

/// Fetches and mutates pull requests through the GitHub CLI so private repositories work
/// with the user's existing `gh` auth.
actor GitHubPullRequestsService: PullRequestsService {
    private static let maxTransientRetries = 2

    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving
    private let decoder: JSONDecoder
    private let reviewBodyWriter: @Sendable (Data) throws -> URL
    private let transientRetryDelay: Duration

    init(
        shellRunner: any ShellRunner = DefaultShellRunner(),
        executableResolver: (any ExecutablePathResolving)? = nil,
        reviewBodyWriter: @escaping @Sendable (Data) throws -> URL = GitHubPullRequestsService.writeReviewBodyFile,
        transientRetryDelay: Duration = .milliseconds(400)
    ) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver ?? DefaultExecutablePathResolver(shell: shellRunner)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.reviewBodyWriter = reviewBodyWriter
        self.transientRetryDelay = transientRetryDelay
    }

    func listInvolvedPullRequests() async throws -> PullRequestListResult {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: ghExecutable,
            args: Self.listArgs,
            timeout: .seconds(30),
            stdoutLimitBytes: 4 * 1024 * 1024
        )
        let decoded = try decodeGraphQL(ListGraphQLData.self, from: result)
        return Self.makeListResult(data: decoded.data, warnings: decoded.warnings)
    }

    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: ghExecutable,
            args: Self.detailArgs(for: id),
            timeout: .seconds(30),
            stdoutLimitBytes: 8 * 1024 * 1024
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

    func submitReview(_ id: PullRequestIdentifier, submission: PendingReviewSubmission) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        let payload = ReviewSubmissionPayload(submission: submission)
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(payload)
        } catch {
            throw PullRequestsServiceError.decodingFailed(error.localizedDescription)
        }
        // ShellRunner has no stdin-data mode, so the JSON body travels through a temp file.
        let bodyFileURL: URL
        do {
            bodyFileURL = try reviewBodyWriter(bodyData)
        } catch {
            throw PullRequestsServiceError.transport(error.localizedDescription)
        }
        defer {
            try? FileManager.default.removeItem(at: bodyFileURL)
        }
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)/reviews",
                "-X", "POST",
                "--input", bodyFileURL.path
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/comments/\(commentID)",
                "-X", "PATCH",
                "-f", "body=\(body)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/comments/\(commentID)",
                "-X", "DELETE"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func replyToReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)/comments/\(commentID)/replies",
                "-X", "POST",
                "-f", "body=\(body)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func setReviewThreadResolved(threadID: String, resolved: Bool) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: Self.threadResolutionArgs(threadID: threadID, resolved: resolved),
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func requestReview(_ id: PullRequestIdentifier, reviewerLogin: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)/requested_reviewers",
                "-X", "POST",
                "-f", "reviewers[]=\(reviewerLogin)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func addReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        try await runReactionMutation(add: true, subjectID: subjectID, content: content)
    }

    func removeReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        try await runReactionMutation(add: false, subjectID: subjectID, content: content)
    }

    private func runReactionMutation(
        add: Bool,
        subjectID: String,
        content: PullRequestReactionContent
    ) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: Self.reactionArgs(add: add, subjectID: subjectID, content: content),
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }
}

extension GitHubPullRequestsService {
    static func writeReviewBodyFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-pr-review-\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}

private extension GitHubPullRequestsService {
    func resolveGitHubCLI() async throws -> String {
        guard let path = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw PullRequestsServiceError.ghNotInstalled
        }
        return path
    }

    /// Read-only calls retry transient GitHub 5xx responses (the GraphQL search
    /// endpoint 502s intermittently). Mutations such as review submission must not
    /// use this — they are not idempotent.
    func runGitHubCLIRetryingTransientFailures(
        executable: String,
        args: [String],
        timeout: Duration,
        stdoutLimitBytes: Int? = 64 * 1024
    ) async throws -> ShellResult {
        var attempt = 0
        while true {
            let result = try await runGitHubCLI(
                executable: executable,
                args: args,
                timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes
            )
            guard !result.succeeded,
                  attempt < Self.maxTransientRetries,
                  Self.isTransientServerFailure(result) else {
                return result
            }
            attempt += 1
            do {
                try await Task.sleep(for: transientRetryDelay * attempt)
            } catch {
                // Cancelled mid-backoff: surface the last failure instead of retrying.
                return result
            }
        }
    }

    static func isTransientServerFailure(_ result: ShellResult) -> Bool {
        guard case .requestFailed(let statusCode) = makeError(from: result) else {
            return false
        }
        return (502...504).contains(statusCode)
    }

    func runGitHubCLI(
        executable: String,
        args: [String],
        timeout: Duration,
        stdoutLimitBytes: Int? = 64 * 1024
    ) async throws -> ShellResult {
        do {
            return try await shellRunner.run(
                executable: executable,
                args: args,
                timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes,
                stderrLimitBytes: 64 * 1024
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

private struct ReviewSubmissionPayload: Encodable {
    struct Comment: Encodable {
        let path: String
        let line: Int
        let side: String
        let body: String
    }

    let event: String
    let body: String
    let comments: [Comment]

    init(submission: PendingReviewSubmission) {
        event = submission.event.rawValue
        body = submission.body
        comments = submission.comments.map { comment in
            Comment(path: comment.path, line: comment.line, side: comment.side.rawValue, body: comment.body)
        }
    }
}
