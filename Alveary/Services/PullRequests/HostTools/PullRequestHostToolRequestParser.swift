import AgentCLIKit
import Foundation

/// Strict argument reading for the pull request tools.
///
/// Parsing is deliberately separate from validation: the canonical hash an exact retry is keyed on
/// has to be derivable from the request alone, before GitHub or host state is consulted, so a retry
/// that arrives after the world changed still replays its recorded result.
struct PullRequestHostToolRequestParser {
    /// `list_involved_prs`. Every argument is optional and every default reproduces the call the
    /// tool has always made: everything the user is involved in, open only, the newest 50 rows.
    ///
    /// A `cursor` is authoritative — it carries the query it is paging, so `{cursor}` alone
    /// continues that search. An argument passed beside it that disagrees is refused rather than
    /// merged; one that agrees is harmless and passes.
    func parseListRequest(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolListRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["filter", "limit", "status", "updated_after", "updated_before", "cursor"])
        let filter = try listFilter(in: object)
        let limit = try listLimit(in: object)
        let status = try listStatus(in: object)
        let updatedAfter = try listDate(in: object, key: "updated_after")
        let updatedBefore = try listDate(in: object, key: "updated_before")
        if let updatedAfter, let updatedBefore, updatedAfter > updatedBefore {
            throw invalid(
                "\(object.path).updated_after must not be later than \(object.path).updated_before."
            )
        }
        guard let rawCursor = try object.optionalNonEmptyString("cursor") else {
            let filter = filter ?? .all
            return PullRequestHostToolListRequest(
                filter: filter,
                limit: limit ?? PullRequestHostToolLimits.maxListRows,
                status: status ?? .open,
                updatedAfter: updatedAfter,
                updatedBefore: updatedBefore,
                buckets: filter.requiredBuckets,
                cursors: [:]
            )
        }
        let token = try PullRequestListCursorToken.decoded(from: rawCursor, path: object.path)
        try requireAgreement(filter, with: token.filter, key: "filter", path: object.path)
        try requireAgreement(limit, with: token.limit, key: "limit", path: object.path)
        try requireAgreement(status, with: token.status, key: "status", path: object.path)
        try requireAgreement(updatedAfter, with: token.updatedAfter, key: "updated_after", path: object.path)
        try requireAgreement(updatedBefore, with: token.updatedBefore, key: "updated_before", path: object.path)
        return PullRequestHostToolListRequest(
            filter: token.filter,
            limit: token.limit,
            status: token.status,
            updatedAfter: token.updatedAfter,
            updatedBefore: token.updatedBefore,
            buckets: Set(token.buckets),
            cursors: token.cursors
        )
    }

    /// The shape every tool that names one pull request and nothing else takes — `get_pr`.
    func parseIdentifier(arguments: [String: AgentCLIKit.JSONValue]) throws -> PullRequestIdentifier {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url"])
        return try Self.identifier(from: object.requiredNonEmptyString("url"))
    }

    func parseTimeline(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolTimelineRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "limit"])
        let limit: Int
        if object.values["limit"] != nil {
            limit = try object.requiredPositiveInteger("limit")
            guard limit <= PullRequestHostToolLimits.maxTimelineLimit else {
                throw invalid(
                    "\(object.path).limit must be at most \(PullRequestHostToolLimits.maxTimelineLimit)."
                )
            }
        } else {
            limit = PullRequestHostToolLimits.defaultTimelineLimit
        }
        return PullRequestHostToolTimelineRequest(
            identifier: try Self.identifier(from: object.requiredNonEmptyString("url")),
            limit: limit
        )
    }

    func parseDiff(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolDiffRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "paths", "offset"])
        let offset: Int
        if object.values["offset"] != nil {
            offset = try object.requiredInteger("offset")
            guard offset >= 0 else {
                throw invalid("\(object.path).offset must be at least 0.")
            }
        } else {
            offset = 0
        }
        return PullRequestHostToolDiffRequest(
            identifier: try Self.identifier(from: object.requiredNonEmptyString("url")),
            paths: try paths(in: object),
            offset: offset
        )
    }

    func parseThreadReply(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolThreadReplyRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "thread_id", "body"])
        let url = try object.requiredNonEmptyString("url")
        let threadID = try object.requiredNonEmptyString("thread_id")
        let body = try object.requiredNonEmptyString("body")
        return PullRequestHostToolThreadReplyRequest(
            identifier: try Self.identifier(from: url),
            threadID: threadID,
            body: body,
            canonicalPayloadHash: try Self.hash(
                tool: PullRequestHostToolCatalog.replyToThreadToolName,
                fields: [
                    "url": .string(url),
                    "thread_id": .string(threadID),
                    "body": .string(body)
                ]
            )
        )
    }

    /// `resolve_pr_thread` and `unresolve_pr_thread` share one shape; which way it
    /// flips is the tool's name, not an argument.
    func parseThreadResolution(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolResolutionRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "thread_id"])
        return PullRequestHostToolResolutionRequest(
            identifier: try Self.identifier(from: object.requiredNonEmptyString("url")),
            threadID: try object.requiredNonEmptyString("thread_id")
        )
    }

    func parseComment(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolCommentRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "body"])
        let url = try object.requiredNonEmptyString("url")
        let body = try object.requiredNonEmptyString("body")
        return PullRequestHostToolCommentRequest(
            identifier: try Self.identifier(from: url),
            body: body,
            canonicalPayloadHash: try Self.hash(
                tool: PullRequestHostToolCatalog.commentToolName,
                fields: ["url": .string(url), "body": .string(body)]
            )
        )
    }

    func parseReviewProposal(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolReviewProposalRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "event", "body", "comments"])
        let url = try object.requiredNonEmptyString("url")
        let rawEvent = try object.requiredNonEmptyString("event")
        guard let event = Self.reviewEvent(from: rawEvent) else {
            throw invalid("\(object.path).event must be one of: \(Self.reviewEventNames.joined(separator: ", ")).")
        }
        let body = try object.optionalNonEmptyString("body")
        let comments = try reviewComments(in: object)
        // Optional fields join the hash only when present, so an omitted field and a blank one
        // read as the same call.
        var hashFields: [String: AgentCLIKit.JSONValue] = [
            "url": .string(url),
            "event": .string(rawEvent)
        ]
        if let body {
            hashFields["body"] = .string(body)
        }
        if let comments {
            hashFields["comments"] = .array(comments.map { comment in
                .object([
                    "path": .string(comment.path),
                    "line": .number(Double(comment.line)),
                    "side": .string(comment.side.rawValue),
                    "body": .string(comment.body)
                ])
            })
        }
        return PullRequestHostToolReviewProposalRequest(
            identifier: try Self.identifier(from: url),
            event: event,
            body: body,
            comments: comments ?? [],
            canonicalPayloadHash: try Self.hash(
                tool: PullRequestHostToolCatalog.proposeReviewToolName,
                fields: hashFields
            )
        )
    }

    /// The tool-facing event names, also what the catalog's enum schema advertises.
    static let reviewEventNames = ["approve", "request_changes", "comment"]

    static func reviewEvent(from raw: String) -> PullRequestReviewEvent? {
        switch raw {
        case "approve":
            .approve
        case "request_changes":
            .requestChanges
        case "comment":
            .comment
        default:
            nil
        }
    }

    static func reviewEventName(for event: PullRequestReviewEvent) -> String {
        switch event {
        case .approve:
            "approve"
        case .requestChanges:
            "request_changes"
        case .comment:
            "comment"
        }
    }
}

private extension PullRequestHostToolRequestParser {
    func listFilter(in object: StrictHostToolObject) throws -> PullRequestHostToolListFilter? {
        guard let raw = try object.optionalNonEmptyString("filter") else {
            return nil
        }
        guard let filter = PullRequestHostToolListFilter(rawValue: raw) else {
            throw invalid(
                "\(object.path).filter must be one of: " +
                    "\(PullRequestHostToolListFilter.allCases.map(\.rawValue).joined(separator: ", "))."
            )
        }
        return filter
    }

    func listLimit(in object: StrictHostToolObject) throws -> Int? {
        guard object.values["limit"] != nil else {
            return nil
        }
        let limit = try object.requiredPositiveInteger("limit")
        guard limit <= PullRequestHostToolLimits.maxListRows else {
            throw invalid("\(object.path).limit must be at most \(PullRequestHostToolLimits.maxListRows).")
        }
        return limit
    }

    /// One status per call: GitHub search qualifiers only AND, so there is no set to accept here —
    /// `PullRequestStatus.searchQualifier` owns why.
    func listStatus(in object: StrictHostToolObject) throws -> PullRequestStatus? {
        guard let raw = try object.optionalNonEmptyString("status") else {
            return nil
        }
        guard let status = PullRequestStatus(rawValue: raw) else {
            throw invalid(
                "\(object.path).status must be one of: " +
                    "\(PullRequestStatus.allCases.map(\.rawValue).joined(separator: ", "))."
            )
        }
        return status
    }

    /// Strict `YYYY-MM-DD` in UTC. A partial or lenient parse would search a window the user never
    /// asked for and report it as theirs.
    func listDate(in object: StrictHostToolObject, key: String) throws -> Date? {
        guard let raw = try object.optionalNonEmptyString(key) else {
            return nil
        }
        guard let date = PullRequestSearchDates.date(fromDay: raw) else {
            throw invalid("\(object.path).\(key) must be a UTC date in YYYY-MM-DD form.")
        }
        return date
    }

    /// An argument passed alongside a cursor may repeat what the cursor already says, but may not
    /// contradict it: paging one search while claiming another is the failure this prevents.
    func requireAgreement<Value: Equatable>(
        _ argument: Value?,
        with token: Value?,
        key: String,
        path: String
    ) throws {
        guard let argument, argument != token else {
            return
        }
        throw invalid(
            "\(path).\(key) disagrees with the search \(path).cursor is paging. Pass cursor on its " +
                "own to continue that search, or omit cursor to start a new one."
        )
    }

    static func identifier(from url: String) throws -> PullRequestIdentifier {
        guard let identifier = PullRequestURLParser.identifier(from: url) else {
            throw PullRequestHostToolServiceError.invalidPullRequestURL(url)
        }
        return identifier
    }

    func side(in object: StrictHostToolObject) throws -> PullRequestDiffSide {
        guard let raw = try object.optionalNonEmptyString("side") else {
            return .right
        }
        guard let side = PullRequestDiffSide(rawValue: raw) else {
            throw invalid("\(object.path).side must be RIGHT or LEFT.")
        }
        return side
    }

    /// Shape only, like `paths(in:)`. Two comments on one line are legal GitHub state and can be
    /// deliberate, so duplicates pass. Nil means the field was omitted — a summary-only proposal;
    /// an empty array is refused rather than silently meaning the same thing.
    func reviewComments(
        in object: StrictHostToolObject
    ) throws -> [PullRequestHostToolReviewCommentItem]? {
        guard let values = try object.optionalArray("comments") else {
            return nil
        }
        guard !values.isEmpty else {
            throw invalid("\(object.path).comments must not be empty; omit it for a summary-only review.")
        }
        guard values.count <= PullRequestHostToolLimits.maxReviewCommentsPerProposal else {
            throw invalid(
                "\(object.path).comments must contain at most " +
                    "\(PullRequestHostToolLimits.maxReviewCommentsPerProposal) comments; " +
                    "keep the most important findings."
            )
        }
        return try values.enumerated().map { index, value in
            guard case .object(let fields) = value else {
                throw invalid("\(object.path).comments[\(index)] must be an object.")
            }
            let comment = StrictHostToolObject(fields, path: "\(object.path).comments[\(index)]")
            try comment.requireOnly(["path", "line", "side", "body"])
            return PullRequestHostToolReviewCommentItem(
                path: try comment.requiredNonEmptyString("path"),
                line: try comment.requiredPositiveInteger("line"),
                side: try side(in: comment),
                body: try comment.requiredNonEmptyString("body")
            )
        }
    }

    /// Shape only. Whether a path exists in the diff is GitHub state, so it
    /// belongs to the handler.
    func paths(in object: StrictHostToolObject) throws -> [String]? {
        guard let values = try object.optionalArray("paths") else {
            return nil
        }
        let paths = try values.enumerated().map { index, value in
            guard case .string(let path) = value else {
                throw invalid("\(object.path).paths[\(index)] must be a string.")
            }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw invalid("\(object.path).paths[\(index)] must not be empty.")
            }
            return trimmed
        }
        guard !paths.isEmpty else {
            throw invalid("\(object.path).paths must not be empty; omit it to include every file.")
        }
        guard Set(paths).count == paths.count else {
            throw invalid("\(object.path).paths must not contain duplicate paths.")
        }
        return paths
    }

    func invalid(_ message: String) -> HostToolRequestError {
        .invalidArguments(message)
    }

    /// Every field that changes what the mutation does, keyed by the tool name so
    /// two tools sharing a field shape cannot replay each other's receipts.
    static func hash(tool: String, fields: [String: AgentCLIKit.JSONValue]) throws -> String {
        var object = fields
        object["tool"] = .string(tool)
        return HostToolDeduplication.sha256(try HostToolDeduplication.canonicalJSON(.object(object)))
    }
}
