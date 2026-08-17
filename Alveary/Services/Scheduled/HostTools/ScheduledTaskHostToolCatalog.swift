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
            tools: tools,
            instructionsFragment: instructionsFragment(
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            )
        )
    }

    static func instructionsFragment(timeZoneIdentifier: String) -> String {
        """
        These tools manage Alveary's local scheduled tasks. Schedule times use the Mac's current local time zone \
        (\(timeZoneIdentifier)). \
        Use scheduling tools only when the user explicitly asks to create, list, edit, pause, resume, delete, or run an Alveary \
        scheduled task. Incidental dates, deadlines, elapsed-time estimates, and phrases such as "later" do not imply a scheduling \
        request. Ask for clarification before proposing a task when its instructions, recurrence, or target are materially ambiguous. \
        For a weekdays schedule, days must list every intended day of the week, including weekend days when \
        requested. Use propose_scheduled_task with action create to create a scheduled task. Call list_scheduled_tasks before edit, \
        pause, resume, delete, or run_now, then use propose_scheduled_task with that action. Never invent or search for a separate \
        create_scheduled_task tool. Call list_projects only when the user wants a scheduled task to run in a different Alveary Project \
        than this conversation's, and list_threads only when they want its results posted into an existing Alveary thread; a scheduled \
        task can target only some listed threads, and proposing one reports which. \
        Pause, resume, and run_now take effect immediately. Create, edit, and delete only \
        open Alveary's native confirmation UI; describe those as opened proposals and never claim the schedule changed before \
        confirmation. Never use shell commands, crontab, launch agents, or workspace files \
        to discover or manage Alveary scheduled tasks. If these tools are unavailable, say so and direct the user to Alveary's \
        Scheduled screen instead of attempting a substitute.
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
        Create, edit, pause, resume, delete, or run now an Alveary scheduled task after the user explicitly requests that action. Pause, \
        resume, and run_now apply immediately and report what changed. Create, edit, and delete open a native confirmation proposal instead \
        and change nothing until the user confirms. Use action create for a new scheduled task; there is no separate create_scheduled_task \
        tool. For create, provide title, prompt, and schedule. For edit, provide task_id, revision, and changes. For pause, resume, delete, \
        or run_now, provide task_id and revision. For existing definitions, call list_scheduled_tasks first and pass its exact task_id and \
        revision. Ask \
        for clarification instead of guessing materially ambiguous instructions, recurrence, or target. Edit changes may replace \
        title, prompt, the complete schedule, or where the task runs. Omit destination and workspace to inherit this conversation's; \
        send destination reused_thread to create one thread on the first run and post every later run into it (the default for new \
        tasks), new_thread for a fresh thread on every run, or existing_thread with a target_thread_id from list_threads to post \
        results into an existing thread. A workspace with a project_path from list_projects runs in a different Project. \
        granted_roots replaces the folder grants \
        the task would otherwise inherit; entries must be absolute paths to existing folders, may combine with a project_path, and \
        every grant is shown to the user for confirmation. Provider, model, effort, permissions, and run location are bound by \
        Alveary and are intentionally not accepted. After it returns, report the `status` \
        it gave back: `applied` means the change is already in effect, and `pending_confirmation` means a proposal was opened and \
        nothing has changed yet.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: proposalProperties,
            required: ["action"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["pending_confirmation", "applied", "error"]),
                "proposal_id": HostToolSchema.stringSchema,
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
        "schedule": scheduleSchema,
        "task_id": HostToolSchema.nonEmptyStringSchema,
        "revision": HostToolSchema.integerSchema(minimum: 1),
        "changes": changesSchema
    ].merging(placementProperties) { current, _ in current }

    static let changesSchema: AgentCLIKit.JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "title": HostToolSchema.nonEmptyStringSchema,
            "prompt": HostToolSchema.nonEmptyStringSchema,
            "schedule": scheduleSchema
        ].merging(placementProperties) { current, _ in current }),
        "minProperties": .number(1),
        "additionalProperties": .bool(false)
    ])

    static let placementProperties: [String: AgentCLIKit.JSONValue] = [
        "destination": HostToolSchema.enumSchema(["reused_thread", "new_thread", "existing_thread"]),
        "target_thread_id": HostToolSchema.nonEmptyStringSchema,
        "workspace": workspaceSchema
    ]

    static let workspaceSchema: AgentCLIKit.JSONValue = HostToolSchema.strictObject(
        properties: [
            "kind": HostToolSchema.enumSchema(["project", "private"]),
            "project_path": HostToolSchema.nonEmptyStringSchema,
            "granted_roots": .object([
                "type": .string("array"),
                "items": HostToolSchema.nonEmptyStringSchema,
                "uniqueItems": .bool(true)
            ])
        ],
        required: ["kind"]
    )

    static let scheduleSchema: AgentCLIKit.JSONValue = HostToolSchema.strictNestedUnionObject(
        properties: scheduleProperties,
        required: ["kind"],
        branches: [
            HostToolSchema.strictObject(
                properties: [
                    "kind": HostToolSchema.enumSchema(["once"]),
                    "at": HostToolSchema.dateTimeSchema
                ],
                required: ["kind", "at"]
            ),
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
    )

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
