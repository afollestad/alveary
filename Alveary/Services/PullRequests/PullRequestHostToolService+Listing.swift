import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Lists the pull requests the signed-in GitHub user is involved in.
    ///
    /// GitHub's search is what bounds this: the service asks for the user's own authored,
    /// review-requested, and reviewed buckets, so there is no way to steer it at an arbitrary
    /// repository. The filter narrows that merged set the same way the Pull Requests screen's tabs
    /// do, so the tool and the UI can never disagree about what "reviewing" means.
    func listPullRequests(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let filter = try parseListFilter(arguments: arguments)

        let result: PullRequestListResult
        do {
            result = try await pullRequestsService.listInvolvedPullRequests()
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }

        let matching = result.summaries.filter(filter.matches)
        // Newest activity first, matching the screen; the display key breaks ties so repeated calls
        // agree on the order.
        let sorted = matching.sorted { lhs, rhs in
            guard lhs.updatedAt == rhs.updatedAt else {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.displayKey < rhs.id.displayKey
        }
        let shown = Array(sorted.prefix(PullRequestHostToolLimits.maxListRows))

        var content: [String: AgentCLIKit.JSONValue] = [
            "filter": .string(filter.rawValue),
            "pull_requests": .array(shown.map(Self.structuredRow)),
            "total_count": .number(Double(matching.count))
        ]
        if !result.warnings.isEmpty {
            content["warnings"] = .array(result.warnings.map(AgentCLIKit.JSONValue.string))
        }
        return AgentCLIKit.AgentHostToolResult(
            text: listText(header: header(filter: filter, shown: shown.count, total: matching.count, warnings: result.warnings),
                           rows: shown.map(Self.textRow)),
            structuredContent: .object(content)
        )
    }
}

private extension PullRequestHostToolService {
    func header(
        filter: PullRequestHostToolListFilter,
        shown: Int,
        total: Int,
        warnings: [String]
    ) -> String {
        var header = "Found \(count(total, singular: "pull request")) (\(filter.rawValue))"
        if shown < total {
            header += ", showing the \(shown) most recently updated"
        }
        if !warnings.isEmpty {
            // The list is genuinely incomplete when an organization refuses the token, so the model
            // must not report it as the user's whole set.
            header += ". Some results were unavailable: \(warnings.joined(separator: "; "))"
        }
        return header
    }

    static func structuredRow(_ summary: PullRequestSummary) -> AgentCLIKit.JSONValue {
        var row: [String: AgentCLIKit.JSONValue] = [
            "repository": .string(summary.id.nameWithOwner),
            "number": .number(Double(summary.id.number)),
            "title": .string(summary.title),
            "status": .string(summary.status.rawValue),
            "author": PullRequestHostToolJSON.author(
                login: summary.authorLogin,
                avatarURL: summary.authorAvatarURL
            ),
            "head_branch": .string(summary.headRefName),
            "base_branch": .string(summary.baseRefName),
            "additions": .number(Double(summary.additions)),
            "deletions": .number(Double(summary.deletions)),
            "involvement": .object([
                "authored": .bool(summary.isAuthored),
                "review_requested": .bool(summary.isReviewRequested),
                "reviewed": .bool(summary.hasReviewed)
            ]),
            "updated_at": .string(PullRequestHostToolDates.canonical(summary.updatedAt))
        ]
        if let url = summary.url {
            row["url"] = .string(url.absoluteString)
        }
        if let reviewDecision = summary.reviewDecision {
            row["review_decision"] = .string(reviewDecision)
        }
        return .object(row)
    }

    static func textRow(_ summary: PullRequestSummary) -> String {
        "- \(summary.id.displayKey) \(summary.title) (\(summary.status.rawValue), " +
            "by \(summary.authorLogin), +\(summary.additions)/-\(summary.deletions))"
    }
}
