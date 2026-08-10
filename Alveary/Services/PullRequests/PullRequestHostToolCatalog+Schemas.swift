import AgentCLIKit
import Foundation

/// The reusable JSON-Schema pieces the pull request tool definitions share, so the read tools
/// describe an author, a reaction, or a review thread the same way everywhere.
extension PullRequestHostToolCatalog {
    static let threadResolutionInputSchema = HostToolSchema.strictObject(
        properties: [
            "url": HostToolSchema.nonEmptyStringSchema,
            "thread_id": HostToolSchema.nonEmptyStringSchema
        ],
        required: ["url", "thread_id"]
    )

    static func threadResolutionOutputSchema(_ statuses: [String]) -> AgentCLIKit.JSONValue {
        HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(statuses),
                "thread_id": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        )
    }

    /// One inline comment `propose_pr_review` takes, anchored to a diff line.
    static let reviewCommentInputSchema = HostToolSchema.strictObject(
        properties: [
            "path": HostToolSchema.nonEmptyStringSchema,
            "line": HostToolSchema.integerSchema(minimum: 1),
            "side": HostToolSchema.enumSchema([
                PullRequestDiffSide.right.rawValue,
                PullRequestDiffSide.left.rawValue
            ]),
            "body": HostToolSchema.nonEmptyStringSchema
        ],
        required: ["path", "line", "body"]
    )

    static func stateChangeOutputSchema(_ statuses: [String]) -> AgentCLIKit.JSONValue {
        HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(statuses),
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        )
    }

    /// Every status the search can run, for both the reported one on a row and the one
    /// `list_involved_prs` accepts as input — so the tool cannot advertise a status it would then
    /// refuse.
    static let statusSchema = HostToolSchema.enumSchema(PullRequestStatus.allCases.map(\.rawValue))

    static let authorSchema = HostToolSchema.strictObject(
        properties: [
            "login": HostToolSchema.stringSchema,
            "avatar_url": HostToolSchema.stringSchema
        ],
        required: ["login"]
    )

    static let reactionSchema = HostToolSchema.strictObject(
        properties: [
            "emoji": HostToolSchema.stringSchema,
            "count": HostToolSchema.integerSchema(minimum: 1),
            "viewer_reacted": HostToolSchema.booleanSchema
        ],
        required: ["emoji", "count", "viewer_reacted"]
    )

    static let reviewerSchema = HostToolSchema.strictObject(
        properties: [
            "login": HostToolSchema.stringSchema,
            "avatar_url": HostToolSchema.stringSchema,
            "state": HostToolSchema.enumSchema(["requested", "approved", "changes_requested", "commented"]),
            "is_bot": HostToolSchema.booleanSchema
        ],
        required: ["login", "state", "is_bot"]
    )

    static let listRowSchema = HostToolSchema.strictObject(
        properties: [
            "repository": HostToolSchema.stringSchema,
            "number": HostToolSchema.integerSchema(minimum: 1),
            "url": HostToolSchema.stringSchema,
            "title": HostToolSchema.stringSchema,
            "status": statusSchema,
            "author": authorSchema,
            "head_branch": HostToolSchema.stringSchema,
            "base_branch": HostToolSchema.stringSchema,
            "additions": HostToolSchema.integerSchema(minimum: 0),
            "deletions": HostToolSchema.integerSchema(minimum: 0),
            "review_decision": HostToolSchema.stringSchema,
            "involvement": HostToolSchema.strictObject(
                properties: [
                    "authored": HostToolSchema.booleanSchema,
                    "review_requested": HostToolSchema.booleanSchema,
                    "reviewed": HostToolSchema.booleanSchema
                ],
                required: ["authored", "review_requested", "reviewed"]
            ),
            "updated_at": HostToolSchema.dateTimeSchema
        ],
        required: [
            "repository", "number", "title", "status", "author",
            "head_branch", "base_branch", "additions", "deletions", "involvement", "updated_at"
        ]
    )

    static let timelineEventSchema = HostToolSchema.strictObject(
        properties: [
            "type": HostToolSchema.enumSchema([
                "opened", "comment", "review", "review_thread", "commit", "force_push",
                "ready_for_review", "converted_to_draft", "closed", "reopened", "merged",
                "review_requested", "review_request_removed"
            ]),
            "actor": authorSchema,
            "at": HostToolSchema.dateTimeSchema,
            "body_markdown": HostToolSchema.stringSchema,
            "body_truncated": HostToolSchema.booleanSchema,
            "reactions": HostToolSchema.arraySchema(items: reactionSchema),
            "verdict": HostToolSchema.enumSchema(["approved", "changes_requested", "commented", "dismissed"]),
            "detail": HostToolSchema.stringSchema,
            "thread_id": HostToolSchema.stringSchema,
            "path": HostToolSchema.stringSchema,
            "line": HostToolSchema.integerSchema(minimum: 1),
            "is_resolved": HostToolSchema.booleanSchema,
            "is_outdated": HostToolSchema.booleanSchema,
            "comment_count": HostToolSchema.integerSchema(minimum: 0),
            "comments": HostToolSchema.arraySchema(items: threadCommentSchema),
            "comments_truncated": HostToolSchema.booleanSchema
        ],
        required: ["type"]
    )

    static let threadCommentSchema = HostToolSchema.strictObject(
        properties: [
            "author": authorSchema,
            "body_markdown": HostToolSchema.stringSchema,
            "body_truncated": HostToolSchema.booleanSchema,
            "created_at": HostToolSchema.dateTimeSchema,
            "reactions": HostToolSchema.arraySchema(items: reactionSchema),
            "is_bot": HostToolSchema.booleanSchema,
            "is_pending": HostToolSchema.booleanSchema
        ],
        required: ["author", "body_markdown", "is_pending"]
    )

    static let diffThreadSchema = HostToolSchema.strictObject(
        properties: [
            "thread_id": HostToolSchema.stringSchema,
            "line": HostToolSchema.integerSchema(minimum: 1),
            "side": HostToolSchema.stringSchema,
            "is_resolved": HostToolSchema.booleanSchema,
            "is_outdated": HostToolSchema.booleanSchema,
            "is_pending": HostToolSchema.booleanSchema,
            "can_reply": HostToolSchema.booleanSchema,
            "comment_count": HostToolSchema.integerSchema(minimum: 0),
            "comments": HostToolSchema.arraySchema(items: threadCommentSchema),
            "comments_truncated": HostToolSchema.booleanSchema
        ],
        required: [
            "is_resolved", "is_outdated", "is_pending", "can_reply",
            "comment_count", "comments", "comments_truncated"
        ]
    )

    static let diffFileSchema = HostToolSchema.strictObject(
        properties: [
            "path": HostToolSchema.stringSchema,
            "previous_path": HostToolSchema.stringSchema,
            "additions": HostToolSchema.integerSchema(minimum: 0),
            "deletions": HostToolSchema.integerSchema(minimum: 0),
            "is_binary": HostToolSchema.booleanSchema,
            "thread_count": HostToolSchema.integerSchema(minimum: 0),
            "patch": HostToolSchema.stringSchema,
            "patch_truncated": HostToolSchema.booleanSchema,
            "threads": HostToolSchema.arraySchema(items: diffThreadSchema)
        ],
        required: ["path", "additions", "deletions", "is_binary", "thread_count"]
    )
}
