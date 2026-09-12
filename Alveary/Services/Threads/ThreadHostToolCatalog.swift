import AgentCLIKit
import Foundation

enum ThreadHostToolCatalog {
    static let featureID = "threads"
    static let listThreadsToolName = "list_threads"
    static let listProjectsToolName = "list_projects"
    static let createThreadToolName = "create_thread"
    static let archiveThreadToolName = "archive_thread"
    static let linkPullRequestToolName = "link_pr"
    static let unlinkPullRequestToolName = "unlink_pr"
    static let listPullRequestsToolName = "list_linked_prs"
    static let pinThreadToolName = "pin_thread"
    static let unpinThreadToolName = "unpin_thread"
    static let createSectionToolName = "create_section"
    static let moveThreadToSectionToolName = "move_thread_to_section"
    static let sendPromptToThreadToolName = "send_prompt_to_thread"

    /// What thread management advertises on the shared `alveary_host` server.
    static var featureCatalog: HostToolFeatureCatalog {
        HostToolFeatureCatalog(
            featureID: featureID,
            title: "Threads",
            tools: tools,
            instructionsFragment: instructionsFragment
        )
    }

    static let instructionsFragment = """
    These tools manage Alveary's own threads — the workspaces in its sidebar — not files, branches, or anything in the \
    user's project. Use them only when the user explicitly asks to list, create, or archive an Alveary thread, or to send \
    one a prompt; wanting a task done is not a request for a new thread. Call list_projects for a project_id, and \
    list_threads for a real thread ID. Leaving create_thread's placement unset puts the new thread wherever this \
    conversation's thread already works and shows it beside this thread in the sidebar, so name a Project, a private \
    workspace, or a section only when the user asks for one. create_thread applies immediately, and an initial prompt \
    starts running in the background right away — its work does not appear in this conversation. \
    archive_thread also applies immediately, stops whatever that thread is doing, and is reversible only by the user from \
    Alveary's Archived screen. No tool here deletes or restores a thread, so never claim a thread was deleted or offer to \
    restore one. A conversation cannot archive its own thread. link_pr and unlink_pr change only Alveary's local record \
    and never touch the pull request on GitHub, so never describe unlink_pr as closing, merging, or deleting one; call it \
    without a url and it resolves the thread's only linked pull request or lists the candidates, so do not ask the user \
    which to remove. list_linked_prs answers only "what is this thread linked to"; it knows nothing the user did not link \
    by hand, so never answer "list my pull requests" or "what needs my review" with it — list_involved_prs searches GitHub \
    for those. Sidebar sections only group threads in the sidebar: create_section adds one at the bottom, and \
    move_thread_to_section changes where a task thread appears, never what it can reach. create_thread's section must \
    already exist, so call create_section first; neither tool creates a section as a side effect. No tool removes or \
    renames a section — only the user can, from the sidebar — so never claim one was removed. send_prompt_to_thread \
    hands a prompt to another thread as if the user typed it there — an idle thread starts on it at once, a busy one \
    queues it behind its current turn — and its work stays in that thread, so never wait for or describe a result here. \
    The recipient is told which thread sent it and answers with the same tool only when the prompt asks for something: \
    never acknowledge or echo a relayed prompt, and never answer an answer, because two threads replying to each other \
    never stop; Alveary refuses an echo and a prompt repeated to the same thread. An answer arrives here as a new user \
    message on a later turn, so end your turn if you are waiting for one. A conversation cannot send a prompt to its \
    own thread. Report each tool's returned `status` rather than describing the change in your own terms.
    """

    /// Tools whose error results carry a `status` field, matching their output schema.
    static let mutatingToolNames: Set<String> = [
        createThreadToolName,
        archiveThreadToolName,
        linkPullRequestToolName,
        unlinkPullRequestToolName,
        pinThreadToolName,
        unpinThreadToolName,
        createSectionToolName,
        moveThreadToSectionToolName,
        sendPromptToThreadToolName
    ]

    static let tools: [AgentCLIKit.AgentHostToolDefinition] = [
        listThreadsTool,
        listProjectsTool,
        createThreadTool,
        archiveThreadTool,
        linkPullRequestTool,
        unlinkPullRequestTool,
        listPullRequestsTool,
        pinThreadTool,
        unpinThreadTool,
        createSectionTool,
        moveThreadToSectionTool,
        sendPromptToThreadTool
    ]
}

private extension ThreadHostToolCatalog {
    static let listProjectsTool = AgentCLIKit.AgentHostToolDefinition(
        name: listProjectsToolName,
        title: "List Alveary Projects",
        description: """
        List registered projects with stable project_id, primary_folder_path, and ordered folders. Projects may have no \
        folders or share folders. Use project_id with create_thread or propose_scheduled_task; legacy project_path only \
        works when it identifies one project unambiguously.
        """,
        inputSchema: HostToolSchema.strictObject(properties: [:], required: []),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "projects": HostToolSchema.arraySchema(
                    items: HostToolSchema.strictObject(
                        properties: [
                            "project_id": HostToolSchema.stringSchema,
                            "path": HostToolSchema.stringSchema,
                            "primary_folder_path": HostToolSchema.stringSchema,
                            "name": HostToolSchema.stringSchema,
                            "folders": HostToolSchema.arraySchema(items: HostToolSchema.strictObject(properties: [
                                "path": HostToolSchema.stringSchema, "name": HostToolSchema.stringSchema,
                                "is_primary": HostToolSchema.booleanSchema, "is_git_repository": HostToolSchema.booleanSchema
                            ], required: ["path", "name", "is_primary", "is_git_repository"]))
                        ],
                        required: ["project_id", "name", "folders"]
                    )
                )
            ],
            required: ["projects"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let listThreadsTool = AgentCLIKit.AgentHostToolDefinition(
        name: listThreadsToolName,
        title: "List Alveary threads",
        description: """
        List the user's active Alveary threads with their current settings. The thread hosting this conversation is marked \
        is_current, which is how you identify where you are running; you cannot archive it or send it a prompt. Use the \
        ID for archive_thread or send_prompt_to_thread, or for propose_scheduled_task's target_thread_id when a scheduled \
        task should post into an existing thread — a scheduled task can only target some of these, and proposing one \
        will say so. Archived and draft threads are never returned. This exposes no conversation content; never use it \
        to browse or read transcripts.
        """,
        inputSchema: HostToolSchema.strictObject(properties: [:], required: []),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "threads": HostToolSchema.arraySchema(
                    items: HostToolSchema.strictObject(
                        properties: [
                            "id": HostToolSchema.stringSchema,
                            "name": HostToolSchema.stringSchema,
                            "workspace": HostToolSchema.stringSchema,
                            "working_directory": HostToolSchema.stringSchema,
                            "granted_roots": HostToolSchema.arraySchema(items: HostToolSchema.stringSchema),
                            "workspace_kind": HostToolSchema.enumSchema(AgentThreadMode.allCases.map(\.rawValue)),
                            "project_path": HostToolSchema.stringSchema,
                            "project_id": HostToolSchema.stringSchema,
                            "primary_folder_path": HostToolSchema.stringSchema,
                            "provider": HostToolSchema.stringSchema,
                            "model": HostToolSchema.stringSchema,
                            "effort": HostToolSchema.stringSchema,
                            "permission_mode": HostToolSchema.stringSchema,
                            "is_pinned": HostToolSchema.booleanSchema,
                            "is_current": HostToolSchema.booleanSchema,
                            "section": HostToolSchema.stringSchema,
                            "modified_at": HostToolSchema.dateTimeSchema
                        ],
                        required: [
                            "id",
                            "name",
                            "workspace",
                            "workspace_kind",
                            "provider",
                            "model",
                            "effort",
                            "permission_mode",
                            "is_pinned",
                            "is_current"
                        ]
                    )
                )
            ],
            required: ["threads"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let createThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: createThreadToolName,
        title: "Create an Alveary thread",
        description: """
        Create a thread when the user explicitly asks. project_id uses that project's current folders; primary_folder_path \
        optionally selects one as primary. Empty projects create a private workspace. Omitted placement inherits this \
        conversation's saved source, grants, and sidebar placement. mode "task" requests a fresh private workspace. \
        granted_roots explicitly replaces additional folders, including [] to remove all; omission preserves defaults. \
        section names an existing section, or Tasks, independently of folder access. Legacy project_path must identify \
        one project unambiguously. Provider, model, and effort inherit this conversation unless specified. initial_prompt \
        dispatches background work to the new thread. Report its returned thread_id; do not wait for the work's outcome.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "mode": HostToolSchema.enumSchema(AgentThreadMode.allCases.map(\.rawValue)),
                "project_path": HostToolSchema.nonEmptyStringSchema,
                "project_id": HostToolSchema.nonEmptyStringSchema,
                "primary_folder_path": HostToolSchema.nonEmptyStringSchema,
                "granted_roots": HostToolSchema.arraySchema(items: HostToolSchema.nonEmptyStringSchema),
                "name": HostToolSchema.nonEmptyStringSchema,
                "provider": HostToolSchema.enumSchema(AppSettings.supportedProviderIDs),
                "model": HostToolSchema.nonEmptyStringSchema,
                "effort": HostToolSchema.nonEmptyStringSchema,
                "permission_mode": HostToolSchema.enumSchema(AppSettings.supportedPermissionModes),
                "initial_prompt": HostToolSchema.nonEmptyStringSchema,
                "pinned": HostToolSchema.booleanSchema,
                "section": HostToolSchema.nonEmptyStringSchema
            ],
            required: []
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["created", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "name": HostToolSchema.stringSchema,
                "workspace_kind": HostToolSchema.enumSchema(AgentThreadMode.allCases.map(\.rawValue)),
                "project_path": HostToolSchema.stringSchema,
                "project_id": HostToolSchema.stringSchema,
                "primary_folder_path": HostToolSchema.stringSchema,
                "granted_roots": HostToolSchema.arraySchema(items: HostToolSchema.stringSchema),
                "provider": HostToolSchema.stringSchema,
                "model": HostToolSchema.stringSchema,
                "effort": HostToolSchema.stringSchema,
                "permission_mode": HostToolSchema.stringSchema,
                "is_pinned": HostToolSchema.booleanSchema,
                "section": HostToolSchema.stringSchema,
                "initial_prompt_dispatched": HostToolSchema.booleanSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let linkPullRequestTool = AgentCLIKit.AgentHostToolDefinition(
        name: linkPullRequestToolName,
        title: "Link a pull request to an Alveary thread",
        description: """
        Attach a GitHub pull request to an Alveary thread, so the user can open it from that thread. Applies immediately, \
        and records a link inside Alveary only — it does not comment on, review, or otherwise change the pull request on \
        GitHub. url must be a github.com pull-request URL or the owner/repo#123 shorthand; Alveary fetches it to confirm \
        it exists, so an unreachable or mistyped one is refused rather than stored. Omit thread_id for the thread hosting \
        this conversation, the usual case; pass one from list_threads to link elsewhere. Alveary may link a pull request \
        on its own the moment its URL appears in the conversation, so already_linked usually means Alveary got there first \
        — report the pull request as linked, not as something the user asked for twice.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "thread_id": HostToolSchema.nonEmptyStringSchema
            ],
            required: ["url"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["linked", "already_linked", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "thread_name": HostToolSchema.stringSchema,
                "pull_request": pullRequestSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let unlinkPullRequestTool = AgentCLIKit.AgentHostToolDefinition(
        name: unlinkPullRequestToolName,
        title: "Remove a pull request link from an Alveary thread",
        description: """
        Remove a GitHub pull request's link from an Alveary thread. Applies immediately and affects Alveary only — the pull \
        request itself is untouched, so never describe this as closing, merging, or deleting it. url takes the same forms \
        as link_pr, and omitting it unlinks the thread's pull request when exactly one is linked, so do not ask the user \
        which one to remove — if several are linked the refusal names them all. Omit thread_id to act on the thread \
        hosting this conversation. Unlinking something that is not linked reports not_linked and changes nothing.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "url": HostToolSchema.nonEmptyStringSchema,
                "thread_id": HostToolSchema.nonEmptyStringSchema
            ],
            required: []
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["unlinked", "not_linked", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "thread_name": HostToolSchema.stringSchema,
                "pull_request": pullRequestSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let listPullRequestsTool = AgentCLIKit.AgentHostToolDefinition(
        name: listPullRequestsToolName,
        title: "List an Alveary thread's linked pull requests",
        description: """
        List the pull requests attached by hand to one Alveary thread, as bookmarks on that thread. Call this only when the \
        user asks what a thread is linked to. It is the wrong tool for "list my pull requests", "what needs my review", or \
        any other request to see the user's pull requests — it reads Alveary's local bookmarks, not GitHub, so answering \
        those with it reports an empty or misleadingly short list as if it were the truth; list_involved_prs searches \
        GitHub and is the tool for all of them. Returns each link newest first. Omit thread_id for the thread hosting this \
        conversation; pass one from list_threads to read another. Each snapshot is from link time and may be stale: use it \
        to identify a pull request, then get_pr for its current state.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["thread_id": HostToolSchema.nonEmptyStringSchema],
            required: []
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "thread_id": HostToolSchema.stringSchema,
                "thread_name": HostToolSchema.stringSchema,
                "pull_requests": HostToolSchema.arraySchema(items: linkedPullRequestSchema)
            ],
            required: ["thread_id", "pull_requests"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let pinThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: pinThreadToolName,
        title: "Pin an Alveary thread",
        description: """
        Pin an Alveary thread so it appears in the sidebar's Pinned section. Applies immediately and is undone with \
        unpin_thread. This affects only where the thread appears, not what it is doing. Call list_threads first and pass \
        one of its exact IDs — its is_pinned field also tells you whether pinning is needed at all. A thread under a \
        pinned project cannot be pinned on its own, because that project already carries it. Pinning an already-pinned \
        thread reports already_pinned and changes nothing.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["thread_id": HostToolSchema.nonEmptyStringSchema],
            required: ["thread_id"]
        ),
        outputSchema: pinOutputSchema(["pinned", "already_pinned", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let unpinThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: unpinThreadToolName,
        title: "Unpin an Alveary thread",
        description: """
        Remove an Alveary thread from the sidebar's Pinned section. Applies immediately and is undone with pin_thread. This \
        only moves where the thread appears — it does not archive the thread, stop its work, or delete anything. Call \
        list_threads first and pass one of its exact IDs. Unpinning a thread that is not pinned reports \
        already_unpinned and changes nothing.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["thread_id": HostToolSchema.nonEmptyStringSchema],
            required: ["thread_id"]
        ),
        outputSchema: pinOutputSchema(["unpinned", "already_unpinned", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let createSectionTool = AgentCLIKit.AgentHostToolDefinition(
        name: createSectionToolName,
        title: "Create an Alveary sidebar section",
        description: """
        Add a named section to Alveary's sidebar, appended below the existing ones, for grouping task threads. Applies \
        immediately and changes only how the sidebar is arranged. Creating a section whose name already exists — \
        including a built-in Pinned, Projects, or Tasks — reports already_exists and changes nothing. No tool removes or \
        renames a section; only the user can, from the sidebar.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["name": HostToolSchema.nonEmptyStringSchema],
            required: ["name"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["created", "already_exists", "error"]),
                "section": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let moveThreadToSectionTool = AgentCLIKit.AgentHostToolDefinition(
        name: moveThreadToSectionToolName,
        title: "Move an Alveary thread to a sidebar section",
        description: """
        Move a task thread into a sidebar section. Applies immediately and changes only where the thread appears, never \
        what it is doing or which folders it can reach. Call list_threads first and pass one of its exact IDs; its \
        section field also tells you whether the move is needed. section takes a custom section's name, or Tasks to move \
        a thread back out of one. The section must already exist — call create_section first. Only task threads live in \
        sections; a thread inside a Project stays with its Project. A thread already there reports already_in_section. \
        Moving a pinned thread unpins it, because a pinned thread renders above the sections.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "thread_id": HostToolSchema.nonEmptyStringSchema,
                "section": HostToolSchema.nonEmptyStringSchema
            ],
            required: ["thread_id", "section"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["moved", "already_in_section", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "name": HostToolSchema.stringSchema,
                "section": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let sendPromptToThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: sendPromptToThreadToolName,
        title: "Send a prompt to an Alveary thread",
        description: """
        Send a prompt to another Alveary thread, as if the user had typed it there. Applies immediately: an idle thread \
        starts a turn on it at once, and a busy thread queues it behind its current turn. Either way the work happens in \
        that thread, not here, so do not wait for a result or describe what it did. That thread is told which thread sent \
        the prompt and may reply with this tool when the prompt asks for an answer; a reply arrives here as a new user \
        message on a later turn. Echoing a relayed prompt back, or repeating one prompt to the same thread, is refused. \
        Call list_threads first and pass one of its exact IDs. A conversation cannot send a prompt to its own thread.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: [
                "thread_id": HostToolSchema.nonEmptyStringSchema,
                "prompt": HostToolSchema.nonEmptyStringSchema
            ],
            required: ["thread_id", "prompt"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["sent", "queued", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "name": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static func pinOutputSchema(_ statuses: [String]) -> AgentCLIKit.JSONValue {
        HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(statuses),
                "thread_id": HostToolSchema.stringSchema,
                "name": HostToolSchema.stringSchema,
                "is_pinned": HostToolSchema.booleanSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        )
    }

    static let pullRequestSchema: AgentCLIKit.JSONValue = HostToolSchema.strictObject(
        properties: pullRequestProperties,
        required: ["repository", "number"]
    )

    /// The link's own timestamp is what `list_linked_prs` adds; everything else is the snapshot
    /// `link_pr` and `unlink_pr` already echo.
    static let linkedPullRequestSchema: AgentCLIKit.JSONValue = HostToolSchema.strictObject(
        properties: pullRequestProperties.merging(["linked_at": HostToolSchema.dateTimeSchema]) { current, _ in current },
        required: ["repository", "number", "linked_at"]
    )

    static let pullRequestProperties: [String: AgentCLIKit.JSONValue] = [
        "repository": HostToolSchema.stringSchema,
        "number": HostToolSchema.integerSchema(minimum: 1),
        "title": HostToolSchema.stringSchema,
        "status": HostToolSchema.stringSchema,
        "url": HostToolSchema.stringSchema
    ]

    static let archiveThreadTool = AgentCLIKit.AgentHostToolDefinition(
        name: archiveThreadToolName,
        title: "Archive an Alveary thread",
        description: """
        Archive an Alveary thread after the user explicitly asks for it. Applies immediately: the thread leaves the \
        sidebar, anything it is running stops, and only the user can bring it back from Alveary's Archived screen. This \
        does not delete the thread and there is no tool that does, so never describe it as deletion. Call list_threads \
        first and pass one of its exact IDs. A conversation cannot archive its own thread. Archiving an already-archived \
        thread reports already_archived and changes nothing.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["thread_id": HostToolSchema.nonEmptyStringSchema],
            required: ["thread_id"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["archived", "already_archived", "error"]),
                "thread_id": HostToolSchema.stringSchema,
                "name": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )
}
