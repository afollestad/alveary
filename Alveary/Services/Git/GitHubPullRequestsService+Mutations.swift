import Foundation

// Every write `GitHubPullRequestsService` performs. None of them retry: unlike
// the reads in the main file, a mutation is not idempotent, so a transient 5xx
// must surface rather than risk posting twice.
extension GitHubPullRequestsService {
    /// Two scalar fields, so plain `-f` pairs carry it like every other mutation
    /// here. Inline comments never travel this way — they are already attached to
    /// the pending review that `submitPendingReview` finishes.
    func submitReview(
        _ id: PullRequestIdentifier,
        event: PullRequestReviewEvent,
        body: String
    ) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)/reviews",
                "-X", "POST",
                "-f", "event=\(event.rawValue)",
                "-f", "body=\(body)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    // MARK: - Pending review
    //
    // The viewer's unsubmitted review. All GraphQL: GitHub publishes no REST
    // endpoint that adds a comment to an existing pending review, and pending
    // comments are addressed by node id rather than the REST ids submitted ones
    // use. Mutations, so none retry.

    func createPendingReview(pullRequestNodeID: String) async throws -> String {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: Self.createPendingReviewArgs(pullRequestNodeID: pullRequestNodeID),
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        let decoded = try decodeGraphQL(CreatePendingReviewGraphQLData.self, from: result)
        guard let reviewID = decoded.data.addPullRequestReview?.pullRequestReview?.id else {
            throw PullRequestsServiceError.transport(
                decoded.warnings.first ?? "GitHub did not return the new review"
            )
        }
        return reviewID
    }

    func addPendingReviewComment(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) async throws -> PullRequestReviewThread {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: Self.addPendingReviewCommentArgs(
                reviewNodeID: reviewNodeID,
                path: path,
                line: line,
                side: side,
                body: body
            ),
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        let decoded = try decodeGraphQL(AddPendingReviewCommentGraphQLData.self, from: result)
        guard let thread = Self.makeReviewThread(from: decoded.data.addPullRequestReviewThread?.thread) else {
            throw PullRequestsServiceError.transport(
                decoded.warnings.first ?? "GitHub did not return the new comment"
            )
        }
        return thread
    }

    func updatePendingReviewComment(commentNodeID: String, body: String) async throws {
        try await runPendingReviewMutation(
            args: Self.updatePendingReviewCommentArgs(commentNodeID: commentNodeID, body: body)
        )
    }

    func deletePendingReviewComment(commentNodeID: String) async throws {
        try await runPendingReviewMutation(
            args: Self.deletePendingReviewCommentArgs(commentNodeID: commentNodeID)
        )
    }

    func deletePendingReview(reviewNodeID: String) async throws {
        try await runPendingReviewMutation(args: Self.deletePendingReviewArgs(reviewNodeID: reviewNodeID))
    }

    func submitPendingReview(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) async throws {
        try await runPendingReviewMutation(
            args: Self.submitPendingReviewArgs(reviewNodeID: reviewNodeID, event: event, body: body)
        )
    }

    /// The pending-review mutations whose payload carries nothing worth reading back.
    private func runPendingReviewMutation(args: [String]) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLI(executable: ghExecutable, args: args, timeout: .seconds(30))
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    // MARK: - Submitted comments

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

    func updateReview(_ id: PullRequestIdentifier, reviewID: Int, body: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried. Review summaries update through PUT on the
        // pull's reviews collection, unlike the PATCH comment endpoints.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)/reviews/\(reviewID)",
                "-X", "PUT",
                "-f", "body=\(body)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func updatePullRequestBody(_ id: PullRequestIdentifier, body: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried. The pull request itself is an issue-like
        // resource, so its body PATCHes on the pulls endpoint.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)",
                "-X", "PATCH",
                "-f", "body=\(body)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func setPullRequestClosed(_ id: PullRequestIdentifier, closed: Bool) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried. Close and reopen are both a `state` PATCH on
        // the pull itself — the same endpoint the description edit uses.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/pulls/\(id.number)",
                "-X", "PATCH",
                "-f", "state=\(closed ? "closed" : "open")"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func markPullRequestReadyForReview(nodeID: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried. Leaving draft has no REST endpoint, so it
        // goes through GraphQL on the pull request's node id.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: Self.readyForReviewArgs(nodeID: nodeID),
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func convertPullRequestToDraft(nodeID: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried. Returning to draft has no REST endpoint
        // either, so it mirrors `markPullRequestReadyForReview` exactly.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: Self.convertToDraftArgs(nodeID: nodeID),
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

    func updateIssueComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried. PR conversation comments are issue comments,
        // so they live under the issues endpoint, not pulls.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/issues/comments/\(commentID)",
                "-X", "PATCH",
                "-f", "body=\(body)"
            ],
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func deleteIssueComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        let ghExecutable = try await resolveGitHubCLI()
        // A mutation: never retried.
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "api", "repos/\(id.nameWithOwner)/issues/comments/\(commentID)",
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

    /// The one non-`api` mutation here: GitHub's `createPullRequest` GraphQL
    /// mutation needs a repository node id, while `gh pr create` resolves the
    /// repository from the working directory and prints the new URL — which is
    /// also how the caller learns the identifier. `--body` rides argv because
    /// `ShellRunner` has no stdin-data mode; `standardInput: .nullDevice` keeps
    /// an unexpected `gh` prompt from hanging the call. A mutation: never retried.
    func createPullRequest(
        inDirectory directory: String,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String
    ) async throws -> PullRequestIdentifier {
        let ghExecutable = try await resolveGitHubCLI()
        let result = try await runGitHubCLI(
            executable: ghExecutable,
            args: [
                "pr", "create",
                "--base", baseBranch,
                "--head", headBranch,
                "--title", title,
                "--body", body
            ],
            in: directory,
            timeout: .seconds(60),
            standardInput: .nullDevice
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        guard let identifier = Self.parseCreatedPullRequestIdentifier(fromStdout: result.stdout) else {
            throw PullRequestsServiceError.decodingFailed(
                "gh pr create did not print the new pull request's URL"
            )
        }
        return identifier
    }

    /// `gh pr create` prints the created pull request's URL as its last stdout
    /// line; earlier lines can carry progress notes, so scan from the end.
    static func parseCreatedPullRequestIdentifier(fromStdout stdout: String) -> PullRequestIdentifier? {
        stdout
            .split(separator: "\n")
            .reversed()
            .lazy
            .compactMap { PullRequestURLParser.identifier(from: String($0).trimmingCharacters(in: .whitespaces)) }
            .first
    }
}
