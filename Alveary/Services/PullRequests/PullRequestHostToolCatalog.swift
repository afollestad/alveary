import AgentCLIKit
import Foundation

enum PullRequestHostToolCatalog {
    static let featureID = "pull_requests"
    /// "Involved", not "mine": the reviewing buckets return other people's pull requests that
    /// await this user's review. The distance from the threads feature's `list_linked_prs` is
    /// deliberate — the two read different sources, and a name that only differed by a middle word
    /// invited the wrong pick.
    static let listToolName = "list_involved_prs"
    static let detailToolName = "get_pr"
    static let timelineToolName = "get_pr_timeline"
    static let diffToolName = "get_pr_diff"
    static let addReviewCommentsToolName = "add_pr_review_comments"
    static let replyToThreadToolName = "reply_to_pr_thread"
    static let resolveThreadToolName = "resolve_pr_thread"
    static let unresolveThreadToolName = "unresolve_pr_thread"
    static let commentToolName = "comment_on_pr"
    static let closeToolName = "close_pr"
    static let reopenToolName = "reopen_pr"
    static let markReadyToolName = "mark_pr_ready"
    static let markDraftToolName = "mark_pr_draft"
    static let proposeReviewToolName = "propose_pr_review"

    /// What pull request access advertises on the shared `alveary_host` server.
    static var featureCatalog: HostToolFeatureCatalog {
        HostToolFeatureCatalog(
            featureID: featureID,
            tools: tools,
            instructionsFragment: instructionsFragment
        )
    }

    static let instructionsFragment = """
    Every question about the user's pull requests is answered by these tools. They run the user's own signed-in GitHub CLI \
    for you, so running gh yourself, searching the web, or opening a github.com URL is never the right move — it can \
    silently answer for the wrong account, and these tools already have the answer. Name a pull request by url: a \
    github.com pull-request URL or the owner/repo#123 shorthand. That claim covers pull requests that already exist. None \
    of these tools creates one, and reopen_pr only revives a closed one, so opening a pull request for the user's local \
    work stays your own git and gh pr create workflow; use these tools on the pull request that results. \
    list_involved_prs answers "list my pull requests", "what needs my review", "what am I working on", and every other \
    request to see them: it searches GitHub for everything the user authors or reviews, including other people's pull \
    requests awaiting their review. Never answer those with the threads feature's list_linked_prs, which reads only what \
    was attached to one Alveary thread by hand and will look empty or misleadingly short. Alveary renders the results as a \
    list the user can click, so answer what they asked instead of repeating the rows back. get_pr, get_pr_timeline, and \
    get_pr_diff read one pull request, and thread_id values come from their output — never invent one. When get_pr_diff \
    returns next_offset, call it again with that offset or narrow it with paths, and copy @@ hunk headers exactly as \
    returned when you quote a patch, because Alveary renders the line numbers from them. propose_pr_review submits nothing \
    itself — it opens a confirmation card where the user can change the verdict and must confirm, so never claim a review \
    was approved, submitted, or rejected; say it awaits the user and report the returned status. Choose the verdict \
    yourself from what you reviewed and call the tool; asking which one to propose is what the card is for, and their \
    answer never comes back to you, so a repeated request is one to propose again rather than a card to wait on. link_pr \
    and unlink_pr (separate tools) attach a pull request to an Alveary thread.
    """

    /// Tools whose error results carry a `status` field, matching their output schema.
    static let mutatingToolNames: Set<String> = [
        addReviewCommentsToolName,
        replyToThreadToolName,
        resolveThreadToolName,
        unresolveThreadToolName,
        commentToolName,
        closeToolName,
        reopenToolName,
        markReadyToolName,
        markDraftToolName,
        proposeReviewToolName
    ]

    static let tools: [AgentCLIKit.AgentHostToolDefinition] = [
        listTool,
        detailTool,
        timelineTool,
        diffTool,
        addReviewCommentsTool,
        replyToThreadTool,
        resolveThreadTool,
        unresolveThreadTool,
        commentTool,
        closeTool,
        reopenTool,
        markReadyTool,
        markDraftTool,
        proposeReviewTool
    ]
}

private extension PullRequestHostToolCatalog {
    static let listTool = AgentCLIKit.AgentHostToolDefinition(
        name: listToolName,
        title: "List the GitHub pull requests the user is involved in",
        description: """
        Search GitHub for the pull requests the signed-in user is involved in, newest activity first. This is the tool for \
        "what pull requests am I working on" or "what needs my review": it queries GitHub live, across every repository. \
        These are not only the user's own pull requests — the reviewing side returns other people's, opened by their \
        authors and waiting on this user. filter narrows to "authored", "reviewing" (asked to review or already \
        reviewed), or "all" (the default). Involvement is the whole search, so it cannot list an arbitrary repository's \
        pull requests, and it is not list_linked_prs, which reads Alveary's local record of what was attached to one \
        thread by hand. Returns up to 50 rows, with total_count reporting how many matched; warnings names organizations \
        whose results were unavailable, usually because the GitHub CLI token lacks their SSO authorization.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["filter": HostToolSchema.enumSchema(PullRequestHostToolListFilter.allCases.map(\.rawValue))],
            required: []
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "filter": HostToolSchema.enumSchema(PullRequestHostToolListFilter.allCases.map(\.rawValue)),
                "pull_requests": HostToolSchema.arraySchema(items: listRowSchema),
                "total_count": HostToolSchema.integerSchema(minimum: 0),
                "warnings": HostToolSchema.arraySchema(items: HostToolSchema.stringSchema)
            ],
            required: ["filter", "pull_requests", "total_count"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let detailTool = AgentCLIKit.AgentHostToolDefinition(
        name: detailToolName,
        title: "Get a GitHub pull request's details",
        description: """
        Read one GitHub pull request's current state: status, author, branches, diff counts, description, reviewers and \
        their verdicts, check counts, and which Alveary threads and projects have it linked. viewer reports the signed-in \
        user's login, whether they have an unsubmitted pending review, and how many pending comments it holds. The \
        description is capped, and description_truncated flags a cut tail. Use get_pr_timeline for the conversation and \
        get_pr_diff for the changes.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "url": HostToolSchema.stringSchema,
                "title": HostToolSchema.stringSchema,
                "status": statusSchema,
                "author": authorSchema,
                "head_branch": HostToolSchema.stringSchema,
                "base_branch": HostToolSchema.stringSchema,
                "created_at": HostToolSchema.dateTimeSchema,
                "updated_at": HostToolSchema.dateTimeSchema,
                "additions": HostToolSchema.integerSchema(minimum: 0),
                "deletions": HostToolSchema.integerSchema(minimum: 0),
                "changed_files": HostToolSchema.integerSchema(minimum: 0),
                "description_markdown": HostToolSchema.stringSchema,
                "description_truncated": HostToolSchema.booleanSchema,
                "description_reactions": HostToolSchema.arraySchema(items: reactionSchema),
                "review_decision": HostToolSchema.stringSchema,
                "reviewers": HostToolSchema.arraySchema(items: reviewerSchema),
                "checks": HostToolSchema.strictObject(
                    properties: [
                        "passing": HostToolSchema.integerSchema(minimum: 0),
                        "failing": HostToolSchema.integerSchema(minimum: 0),
                        "pending": HostToolSchema.integerSchema(minimum: 0)
                    ],
                    required: ["passing", "failing", "pending"]
                ),
                "linked_threads": HostToolSchema.arraySchema(
                    items: HostToolSchema.strictObject(
                        properties: [
                            "thread_id": HostToolSchema.stringSchema,
                            "name": HostToolSchema.stringSchema
                        ],
                        required: ["name"]
                    )
                ),
                "linked_projects": HostToolSchema.arraySchema(
                    items: HostToolSchema.strictObject(
                        properties: [
                            "name": HostToolSchema.stringSchema,
                            "path": HostToolSchema.stringSchema
                        ],
                        required: ["name", "path"]
                    )
                ),
                "counts": HostToolSchema.strictObject(
                    properties: [
                        "comments": HostToolSchema.integerSchema(minimum: 0),
                        "review_threads": HostToolSchema.integerSchema(minimum: 0),
                        "unresolved_threads": HostToolSchema.integerSchema(minimum: 0)
                    ],
                    required: ["comments", "review_threads", "unresolved_threads"]
                ),
                "viewer": HostToolSchema.strictObject(
                    properties: [
                        "login": HostToolSchema.stringSchema,
                        "has_pending_review": HostToolSchema.booleanSchema,
                        "pending_comment_count": HostToolSchema.integerSchema(minimum: 0)
                    ],
                    required: ["has_pending_review", "pending_comment_count"]
                )
            ],
            required: [
                "repository",
                "number",
                "title",
                "status",
                "author",
                "head_branch",
                "base_branch",
                "additions",
                "deletions",
                "changed_files",
                "description_markdown",
                "description_truncated",
                "reviewers",
                "linked_threads",
                "linked_projects",
                "counts",
                "viewer"
            ]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let timelineTool = AgentCLIKit.AgentHostToolDefinition(
        name: timelineToolName,
        title: "Get a GitHub pull request's timeline",
        description: """
        Read one GitHub pull request's conversation chronologically: comments, reviews with their verdicts, review threads, \
        pushed commits, state transitions, and review requests. Returns the newest limit entries (default \
        \(PullRequestHostToolLimits.defaultTimelineLimit), max \(PullRequestHostToolLimits.maxTimelineLimit)), oldest \
        first within that window; total_count and shown_count say what was left out. Bodies are capped, with per-entry \
        truncation flags. Review-thread entries carry the thread_id that reply_to_pr_thread and resolve_pr_thread take.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "limit": HostToolSchema.integerSchema(minimum: 1, maximum: PullRequestHostToolLimits.maxTimelineLimit)
            ],
            required: ["url"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "total_count": HostToolSchema.integerSchema(minimum: 0),
                "shown_count": HostToolSchema.integerSchema(minimum: 0),
                "events": HostToolSchema.arraySchema(items: timelineEventSchema)
            ],
            required: ["repository", "number", "total_count", "shown_count", "events"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let diffTool = AgentCLIKit.AgentHostToolDefinition(
        name: diffToolName,
        title: "Get a GitHub pull request's diff with review threads",
        description: """
        Read one GitHub pull request's diff with its review comment threads attached to the lines they discuss. Every \
        response lists every changed file with its counts and thread_count; patch text is included for as many whole files \
        as fit the output budget, starting at offset (a file index, default 0). When next_offset is returned, more files \
        remain — call again with that offset, or pass paths to read only the named files. Threads carry the thread_id that \
        reply_to_pr_thread and resolve_pr_thread take; pending ones are the user's own unsubmitted draft comments.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "paths": HostToolSchema.arraySchema(items: HostToolSchema.nonEmptyStringSchema),
                "offset": HostToolSchema.integerSchema(minimum: 0)
            ],
            required: ["url"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "total_files": HostToolSchema.integerSchema(minimum: 0),
                "patches_included": HostToolSchema.booleanSchema,
                "next_offset": HostToolSchema.integerSchema(minimum: 0),
                "files": HostToolSchema.arraySchema(items: diffFileSchema),
                "guidance": HostToolSchema.stringSchema
            ],
            required: ["repository", "number", "total_files", "patches_included", "files"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let addReviewCommentsTool = AgentCLIKit.AgentHostToolDefinition(
        name: addReviewCommentsToolName,
        title: "Add pending review comments to pull request diff lines",
        description: """
        Attach inline review comments to diff lines, as part of the user's pending draft review on GitHub — creating that \
        draft if none exists. Pass every comment for the review in one call. Nothing is published to other people: they \
        are visible only to the user until a review is submitted, and they can edit or delete each one from Alveary's \
        pull request pane, so this applies immediately without confirmation. path and line must come from get_pr_diff; \
        side is RIGHT (the new code, the default) or LEFT (the old code, for deleted lines). Comments apply in order and \
        stop at the first failure, reported per comment. Submitting the review is a separate, user-confirmed step via \
        propose_pr_review.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "comments": HostToolSchema.arraySchema(
                    items: reviewCommentInputSchema,
                    minItems: 1,
                    maxItems: PullRequestHostToolLimits.maxReviewCommentsPerCall
                )
            ],
            required: ["url", "comments"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["added", "partial", "error"]),
                "comments": HostToolSchema.arraySchema(items: reviewCommentResultSchema),
                "added_count": HostToolSchema.integerSchema(minimum: 0),
                "pending_comment_count": HostToolSchema.integerSchema(minimum: 0),
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let replyToThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: replyToThreadToolName,
        title: "Reply to a pull request review thread",
        description: """
        Reply to an existing review thread on a pull request. Posts to GitHub immediately and publicly — there is no draft \
        step — so call it only with content the user asked to post; the user can delete the reply afterward. thread_id must \
        come from get_pr_diff or get_pr_timeline. A thread that is part of the user's unsubmitted pending review takes no \
        replies until that review is submitted.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "thread_id": HostToolSchema.nonEmptyStringSchema,
                "body": HostToolSchema.nonEmptyStringSchema
            ],
            required: ["url", "thread_id", "body"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["replied", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let resolveThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: resolveThreadToolName,
        title: "Resolve a pull request review thread",
        description: """
        Mark a review thread resolved on GitHub. Applies immediately and is undone with unresolve_pr_thread. thread_id must \
        come from get_pr_diff or get_pr_timeline. Resolving an already-resolved thread reports already_resolved and changes \
        nothing.
        """,
        inputSchema: threadResolutionInputSchema,
        outputSchema: threadResolutionOutputSchema(["resolved", "already_resolved", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let unresolveThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: unresolveThreadToolName,
        title: "Unresolve a pull request review thread",
        description: """
        Reopen a resolved review thread on GitHub. Applies immediately and is undone with resolve_pr_thread. thread_id must \
        come from get_pr_diff or get_pr_timeline. Unresolving a thread that is not resolved reports already_unresolved and \
        changes nothing.
        """,
        inputSchema: threadResolutionInputSchema,
        outputSchema: threadResolutionOutputSchema(["unresolved", "already_unresolved", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let commentTool = AgentCLIKit.AgentHostToolDefinition(
        name: commentToolName,
        title: "Comment on a pull request",
        description: """
        Post a top-level comment on a pull request's conversation, outside any review. Posts to GitHub immediately and \
        publicly — there is no draft step — so call it only with content the user asked to post; the user can edit or \
        delete it afterward. For comments on specific diff lines, use add_pr_review_comments instead.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "body": HostToolSchema.nonEmptyStringSchema
            ],
            required: ["url", "body"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["commented", "error"]),
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let proposeReviewTool = AgentCLIKit.AgentHostToolDefinition(
        name: proposeReviewToolName,
        title: "Propose submitting a pull request review",
        description: """
        Propose submitting the user's review of a pull request: approve, request_changes, or comment, with an optional \
        summary body. Nothing reaches GitHub from this tool — it opens a confirmation card where the user can adjust the \
        verdict and must confirm, so never report the review as submitted; pending_confirmation means it awaits them. \
        Pick event yourself from what you reviewed; do not ask the user which verdict to propose, because adjusting it is \
        what the card is for. \
        Submitting publishes their pending draft comments too, and the card shows them. request_changes needs a body; \
        comment needs a body or at least one pending comment; approve and request_changes are refused on the user's own \
        pull request. Propose once and stop — do not re-propose on your own while one is pending, and do not treat later \
        conversation turns as the user's confirmation. Their decision never reaches you: confirming and cancelling both \
        resolve the card inside Alveary and send nothing back, so a later request for a review is one to propose afresh, \
        not the earlier card to wait on.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "event": HostToolSchema.enumSchema(PullRequestHostToolRequestParser.reviewEventNames),
                "body": HostToolSchema.nonEmptyStringSchema
            ],
            required: ["url", "event"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["pending_confirmation", "error"]),
                "proposal_id": HostToolSchema.stringSchema,
                "event": HostToolSchema.enumSchema(PullRequestHostToolRequestParser.reviewEventNames),
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "pending_comment_count": HostToolSchema.integerSchema(minimum: 0),
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )
}
