import AgentCLIKit
import Foundation

/// Strict argument reading for the pull request tools.
///
/// Parsing is deliberately separate from validation: the canonical hash an exact retry is keyed on
/// has to be derivable from the request alone, before GitHub or host state is consulted, so a retry
/// that arrives after the world changed still replays its recorded result.
struct PullRequestHostToolRequestParser {
    /// `list_involved_prs`. An omitted filter means everything the user is involved in.
    func parseListFilter(arguments: [String: AgentCLIKit.JSONValue]) throws -> PullRequestHostToolListFilter {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["filter"])
        guard let raw = try object.optionalNonEmptyString("filter") else {
            return .all
        }
        guard let filter = PullRequestHostToolListFilter(rawValue: raw) else {
            throw invalid(
                "\(object.path).filter must be one of: " +
                    "\(PullRequestHostToolListFilter.allCases.map(\.rawValue).joined(separator: ", "))."
            )
        }
        return filter
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
