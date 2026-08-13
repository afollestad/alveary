import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Lists the pull requests the signed-in GitHub user is involved in.
    ///
    /// GitHub's search is what bounds this: the service asks for the user's own authored,
    /// review-requested, and reviewed buckets, so there is no way to steer it at an arbitrary
    /// repository. The filter picks which of those to fetch, so every narrow filter costs one
    /// search rather than three, and narrows the merged set to the same rows the Pull Requests
    /// screen puts under the matching *section* — `reviewing` is what awaits the user's review,
    /// never what they already reviewed.
    ///
    /// Open by default: this answers "what is on my plate", where a merged or closed pull request
    /// is noise, and unlike the screen there is no user session carrying a choice. `status` is what
    /// asks for a different one, a single value because GitHub search qualifiers only AND.
    ///
    /// Paging is cursor-based. `next_cursor` rides in both the structured content *and* the text
    /// fallback, because a text-only consumer that never sees it cannot ask for page two.
    func listPullRequests(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let request = try parseListRequest(arguments: arguments)

        let result = try await fetchList(request: request)
        // Every fetched row goes to `link_pr`'s fetch-skipping path, pre-filter and pre-limit —
        // the fetch proved them all reachable, which is the only thing that path relies on.
        summaryHandoff.record(result.summaries)

        let matching = result.summaries.filter(request.filter.matches)
        // Newest activity first, matching the screen; the display key breaks ties so repeated calls
        // agree on the order.
        let sorted = matching.sorted { lhs, rhs in
            guard lhs.updatedAt == rhs.updatedAt else {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.displayKey < rhs.id.displayKey
        }
        let shown = Array(sorted.prefix(request.limit))
        let nextCursor = try Self.nextCursor(request: request, result: result, shown: shown)

        var content: [String: AgentCLIKit.JSONValue] = [
            "filter": .string(request.filter.rawValue),
            "pull_requests": .array(shown.map(Self.structuredRow)),
            "total_count": .number(Double(matching.count))
        ]
        if !result.warnings.isEmpty {
            content["warnings"] = .array(result.warnings.map(AgentCLIKit.JSONValue.string))
        }
        if let nextCursor {
            content["next_cursor"] = .string(nextCursor)
        }
        let header = header(
            request: request,
            shown: shown.count,
            total: matching.count,
            warnings: result.warnings
        )
        return AgentCLIKit.AgentHostToolResult(
            text: Self.appendingCursor(
                to: listText(header: header, rows: shown.map(Self.textRow)),
                cursor: nextCursor
            ),
            structuredContent: .object(content)
        )
    }
}

private extension PullRequestHostToolService {
    /// The search itself, with a service failure mapped to the tool's `unavailable` refusal;
    /// anything else propagates untouched.
    func fetchList(request: PullRequestHostToolListRequest) async throws -> PullRequestListResult {
        do {
            return try await pullRequestsService.listInvolvedPullRequests(
                buckets: request.buckets,
                status: request.status,
                options: PullRequestListOptions(
                    pageSize: request.limit,
                    cursors: request.cursors,
                    updatedAfter: request.updatedAfter,
                    updatedBefore: request.updatedBefore
                )
            )
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
    }

    /// The token the next page resumes from, or nil when every bucket is drained.
    ///
    /// A row is *consumed* once it has been emitted or rejected by the filter — no later page can
    /// change either — and each bucket advances past its consumed prefix rather than to its page
    /// boundary, since only the newest `limit` rows of the merged buckets went out.
    /// `PullRequestListCursorAdvance` owns that rule; a bucket whose leg failed has no page info
    /// and is dropped, so a failure cannot be paged past.
    static func nextCursor(
        request: PullRequestHostToolListRequest,
        result: PullRequestListResult,
        shown: [PullRequestSummary]
    ) throws -> String? {
        let emitted = Set(shown.map(\.id))
        var buckets: [PullRequestInvolvementBucket] = []
        var cursors: [PullRequestInvolvementBucket: String] = [:]
        for bucket in PullRequestInvolvementBucket.allCases where request.buckets.contains(bucket) {
            guard let pageInfo = result.pageInfoByBucket[bucket] else {
                continue
            }
            let outcome = PullRequestListCursorAdvance.outcome(
                pageInfo: pageInfo,
                summaries: result.summariesByBucket[bucket] ?? [],
                incoming: request.cursors[bucket],
                isConsumed: { emitted.contains($0.id) || !request.filter.matches($0) }
            )
            switch outcome {
            case .exhausted:
                continue
            case .restart:
                buckets.append(bucket)
            case .resume(let cursor):
                buckets.append(bucket)
                cursors[bucket] = cursor
            }
        }
        guard !buckets.isEmpty else {
            return nil
        }
        return try PullRequestListCursorToken(
            filter: request.filter,
            limit: request.limit,
            status: request.status,
            updatedAfter: request.updatedAfter,
            updatedBefore: request.updatedBefore,
            buckets: buckets,
            cursors: cursors
        ).encoded()
    }

    /// Its own trailing line rather than a row, so `PullRequestListWidgetParsing`'s text fallback —
    /// which reads only lines beginning `- ` — keeps ignoring it.
    static func appendingCursor(to text: String, cursor: String?) -> String {
        guard let cursor else {
            return text
        }
        return text + "\nMore results are available — call list_involved_prs again with cursor: \(cursor)"
    }

    /// The status rides in the sentence rather than the parenthetical, which stays the filter
    /// alone: the transcript card's text fallback finds the filter by matching `(<filter>)`.
    func header(
        request: PullRequestHostToolListRequest,
        shown: Int,
        total: Int,
        warnings: [String]
    ) -> String {
        var header = "Found \(count(total, singular: "\(request.status.rawValue) pull request")) " +
            "(\(request.filter.rawValue))"
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
        // No `review_decision`: the list search does not fetch it, so a row could only ever omit
        // it. `get_pr` reads it for a model that needs one pull request's verdict.
        return .object(row)
    }

    /// The involvement phrase rides *inside* the trailing parenthetical because the transcript
    /// card's text fallback reads that shape: it takes the last `(` as the metadata start and the
    /// first comma-separated component as the status, so appending leaves both untouched.
    static func textRow(_ summary: PullRequestSummary) -> String {
        let metadata = [
            summary.status.rawValue,
            "by \(summary.authorLogin)",
            "+\(summary.additions)/-\(summary.deletions)",
            involvementPhrase(summary)
        ].compactMap { $0 }
        return "- \(summary.id.displayKey) \(summary.title) (\(metadata.joined(separator: ", ")))"
    }

    /// What the structured half carries as `involvement`, for the text-only consumers that never
    /// see it — without this a `filter: "all"` row cannot say whether it awaits the user's review
    /// or already had it. Split like the screen's sections: a re-request reads as pending, and an
    /// authored-only row adds nothing, since its author is already on the line.
    static func involvementPhrase(_ summary: PullRequestSummary) -> String? {
        if summary.isReviewRequested {
            return "review requested"
        }
        return summary.hasReviewed ? "already reviewed" : nil
    }
}
