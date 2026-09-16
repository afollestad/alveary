import AgentCLIKit
import Foundation

enum ScheduledTaskHostToolCatalog {
    static let featureID = "scheduling"
    static let listToolName = "list_scheduled_tasks"
    static let proposeToolName = "propose_scheduled_task"

    /// What scheduling advertises on the shared `alveary_host` server.
    static var featureCatalog: HostToolFeatureCatalog {
        HostToolFeatureCatalog(
            featureID: featureID,
            title: "Scheduled tasks",
            tools: tools,
            instructionsFragment: instructionsFragment(
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            )
        )
    }

    static func instructionsFragment(timeZoneIdentifier: String) -> String {
        """
        Manage Alveary's local scheduled tasks using the Mac's current time zone (\(timeZoneIdentifier)). \
        Act only on explicit scheduling requests. For "In 30 minutes, say hello", call propose_scheduled_task with \
        {"action":"create","title":"Say hello","prompt":"Say hello.","schedule":{"kind":"once","after_seconds":1800}}. \
        Omitted destination defaults to the exact calling \
        conversation, including secondary tabs. Do not list threads to target the caller. Use current_thread explicitly if useful; \
        choose new_thread or reused_thread only when the user requests a separate thread. Call list_threads only to target another \
        existing thread, and list_projects only to choose a different Project. One-off creates, pause, resume, and run_now apply \
        immediately. Recurring creates, edits, and deletes open confirmation proposals. Report the returned status accurately. \
        Call list_scheduled_tasks before edit, pause, resume, delete, or run_now and use its IDs and revisions. \
        Incidental dates, deadlines, time estimates, and "later" alone are not scheduling requests; clarify material ambiguity. \
        Weekday schedules list every requested day. Never invent create_scheduled_task or use shell commands, crontab, launch agents, \
        or workspace files as substitutes. If unavailable, direct the user to Alveary's Scheduled screen.
        """
    }

    static let tools: [AgentCLIKit.AgentHostToolDefinition] = [
        listTool,
        proposeTool
    ]
}

private extension ScheduledTaskHostToolCatalog {
    static let listTool = AgentCLIKit.AgentHostToolDefinition(
        name: listToolName,
        title: "List scheduled tasks",
        description: """
        List Alveary scheduled-task definitions when the user asks what is scheduled, or before targeting an existing definition for \
        edit, pause, resume, delete, or run-now. Returns stable IDs, revisions, titles, states, and schedule summaries; it never returns \
        task prompts. Do not call for ordinary project tasks, calendar discussion, deadlines, or incidental time language.
        """,
        inputSchema: HostToolSchema.strictObject(properties: [:], required: []),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "tasks": .object([
                    "type": .string("array"),
                    "items": HostToolSchema.strictObject(
                        properties: [
                            "id": HostToolSchema.stringSchema,
                            "revision": HostToolSchema.integerSchema(minimum: 1),
                            "title": HostToolSchema.stringSchema,
                            "state": HostToolSchema.enumSchema(["active", "paused", "completed"]),
                            "schedule_summary": HostToolSchema.stringSchema
                        ],
                        required: ["id", "revision", "title", "state", "schedule_summary"]
                    )
                ])
            ],
            required: ["tasks"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )

    static let proposeTool = AgentCLIKit.AgentHostToolDefinition(
        name: proposeToolName,
        title: "Propose a scheduled task change",
        description: """
        Create or change a scheduled task on explicit request. One-off creates apply immediately; recurring creates, edits, and deletes \
        require native confirmation. Pause, resume, and run_now apply immediately. For create, supply title, prompt, and schedule; \
        once accepts either at (RFC 3339 with offset) or after_seconds (positive integer delay from acceptance). For edit, supply task_id, \
        revision, and changes. Other actions require task_id and revision from list_scheduled_tasks. Edits use absolute schedules. \
        Creates default to current_thread: the exact calling conversation, with no target ID or workspace overrides. Explicit new_thread \
        creates a fresh thread per run; reused_thread creates one on the first run and reuses it. existing_thread takes target_thread_id \
        from list_threads. Create workspace overrides require new_thread or reused_thread; project_id comes from list_projects and \
        granted_roots replaces inherited grants with existing absolute folders. Omitted edit placement preserves its target. \
        Harness, model, effort, permissions, and run location are host-bound. Report applied as created/changed and pending_confirmation \
        as an opened proposal. Never claim a proposal has already changed a schedule.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: proposalProperties,
            required: ["action"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["pending_confirmation", "applied", "error"]),
                "proposal_id": HostToolSchema.stringSchema,
                "task_id": HostToolSchema.stringSchema,
                "scheduled_at": HostToolSchema.dateTimeSchema,
                "destination": HostToolSchema.enumSchema(["current_thread", "new_thread", "reused_thread", "existing_thread"]),
                "project_id": HostToolSchema.stringSchema,
                "primary_folder_path": HostToolSchema.stringSchema,
                "granted_roots": HostToolSchema.arraySchema(items: HostToolSchema.stringSchema),
                "action": HostToolSchema.enumSchema(ScheduledTaskProposalAction.allCases.map(\.rawValue)),
                "title": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let proposalProperties: [String: AgentCLIKit.JSONValue] = [
        "action": HostToolSchema.enumSchema(ScheduledTaskProposalAction.allCases.map(\.rawValue)),
        "title": HostToolSchema.nonEmptyStringSchema,
        "prompt": HostToolSchema.nonEmptyStringSchema,
        "schedule": scheduleSchema(allowsRelative: true),
        "task_id": HostToolSchema.nonEmptyStringSchema,
        "revision": HostToolSchema.integerSchema(minimum: 1),
        "changes": changesSchema
    ].merging(placementProperties(includesCurrentThread: true)) { current, _ in current }

    static let changesSchema: AgentCLIKit.JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "title": HostToolSchema.nonEmptyStringSchema,
            "prompt": HostToolSchema.nonEmptyStringSchema,
            "schedule": scheduleSchema(allowsRelative: false)
        ].merging(placementProperties(includesCurrentThread: false)) { current, _ in current }),
        "minProperties": .number(1),
        "additionalProperties": .bool(false)
    ])

    static func placementProperties(includesCurrentThread: Bool) -> [String: AgentCLIKit.JSONValue] {
        [
            "destination": HostToolSchema.enumSchema(
                (includesCurrentThread ? ["current_thread"] : []) + ["reused_thread", "new_thread", "existing_thread"]
            ),
            "target_thread_id": HostToolSchema.nonEmptyStringSchema,
            "workspace": workspaceSchema
        ]
    }

    static let workspaceSchema: AgentCLIKit.JSONValue = HostToolSchema.strictObject(
        properties: [
            "kind": HostToolSchema.enumSchema(["project", "private"]),
            "project_path": HostToolSchema.nonEmptyStringSchema,
            "project_id": HostToolSchema.nonEmptyStringSchema,
            "primary_folder_path": HostToolSchema.nonEmptyStringSchema,
            "granted_roots": .object([
                "type": .string("array"),
                "items": HostToolSchema.nonEmptyStringSchema,
                "uniqueItems": .bool(true)
            ])
        ],
        required: ["kind"]
    )

    static func scheduleSchema(allowsRelative: Bool) -> AgentCLIKit.JSONValue {
        var branches = [HostToolSchema.strictObject(
            properties: ["kind": HostToolSchema.enumSchema(["once"]), "at": HostToolSchema.dateTimeSchema],
            required: ["kind", "at"]
        )]
        if allowsRelative {
            branches.append(HostToolSchema.strictObject(
                properties: ["kind": HostToolSchema.enumSchema(["once"]), "after_seconds": HostToolSchema.integerSchema(minimum: 1)],
                required: ["kind", "after_seconds"]
            ))
        }
        return HostToolSchema.strictNestedUnionObject(
            properties: allowsRelative
                ? scheduleProperties.merging(["after_seconds": HostToolSchema.integerSchema(minimum: 1)]) { _, value in value }
                : scheduleProperties,
            required: ["kind"],
            branches: branches + repeatingScheduleBranches
        )
    }

    static let repeatingScheduleBranches: [AgentCLIKit.JSONValue] = [
        HostToolSchema.strictObject(
            properties: [
                "kind": HostToolSchema.enumSchema(["interval"]),
                "minutes": HostToolSchema.integerSchema(minimum: 1),
                "anchor_at": HostToolSchema.dateTimeSchema
            ],
            required: ["kind", "minutes", "anchor_at"]
        ),
        wallClockScheduleSchema(kind: "daily"),
        HostToolSchema.strictObject(
            properties: [
                "kind": HostToolSchema.enumSchema(["weekdays"]),
                "days": weekdayListSchema,
                "hour": HostToolSchema.integerSchema(minimum: 0, maximum: 23),
                "minute": HostToolSchema.integerSchema(minimum: 0, maximum: 59)
            ],
            required: ["kind", "days", "hour", "minute"]
        ),
        HostToolSchema.strictObject(
            properties: [
                "kind": HostToolSchema.enumSchema(["weekly"]),
                "weekday": HostToolSchema.enumSchema(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
                "hour": HostToolSchema.integerSchema(minimum: 0, maximum: 23),
                "minute": HostToolSchema.integerSchema(minimum: 0, maximum: 59)
            ],
            required: ["kind", "weekday", "hour", "minute"]
        ),
        HostToolSchema.strictObject(
            properties: [
                "kind": HostToolSchema.enumSchema(["monthly"]),
                "day": HostToolSchema.integerSchema(minimum: 1, maximum: 31),
                "hour": HostToolSchema.integerSchema(minimum: 0, maximum: 23),
                "minute": HostToolSchema.integerSchema(minimum: 0, maximum: 59)
            ],
            required: ["kind", "day", "hour", "minute"]
        )
    ]

    static let scheduleProperties: [String: AgentCLIKit.JSONValue] = [
        "kind": HostToolSchema.enumSchema(["once", "interval", "daily", "weekdays", "weekly", "monthly"]),
        "at": HostToolSchema.dateTimeSchema,
        "minutes": HostToolSchema.integerSchema(minimum: 1),
        "anchor_at": HostToolSchema.dateTimeSchema,
        "days": weekdayListSchema,
        "weekday": HostToolSchema.enumSchema(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
        "day": HostToolSchema.integerSchema(minimum: 1, maximum: 31),
        "hour": HostToolSchema.integerSchema(minimum: 0, maximum: 23),
        "minute": HostToolSchema.integerSchema(minimum: 0, maximum: 59)
    ]

    static func wallClockScheduleSchema(kind: String) -> AgentCLIKit.JSONValue {
        HostToolSchema.strictObject(
            properties: [
                "kind": HostToolSchema.enumSchema([kind]),
                "hour": HostToolSchema.integerSchema(minimum: 0, maximum: 23),
                "minute": HostToolSchema.integerSchema(minimum: 0, maximum: 59)
            ],
            required: ["kind", "hour", "minute"]
        )
    }

    static var weekdayListSchema: AgentCLIKit.JSONValue {
        .object([
            "type": .string("array"),
            "items": HostToolSchema.enumSchema(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
            "minItems": .number(1),
            "maxItems": .number(7),
            "uniqueItems": .bool(true)
        ])
    }
}
