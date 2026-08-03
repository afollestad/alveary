import AgentCLIKit
import Foundation

enum ScheduledTaskHostToolCatalog {
    static let listToolName = "list_scheduled_tasks"
    static let listProjectsToolName = "list_projects"
    static let listThreadsToolName = "list_threads"
    static let proposeToolName = "propose_scheduled_task"

    /// Read-only tools that take no arguments.
    static let listToolNames: Set<String> = [listToolName, listProjectsToolName, listThreadsToolName]

    static var serverMetadata: AgentCLIKit.AgentHostToolServerMetadata {
        serverMetadata(timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier)
    }

    static func serverMetadata(timeZoneIdentifier: String) -> AgentCLIKit.AgentHostToolServerMetadata {
        AgentCLIKit.AgentHostToolServerMetadata(
            name: "alveary_host",
            title: "Alveary scheduling",
            instructions: """
            These tools manage Alveary's local scheduled tasks. Schedule times use the Mac's current local time zone \
            (\(timeZoneIdentifier)). \
            Use scheduling tools only when the user explicitly asks to create, list, edit, pause, resume, delete, or run an Alveary \
            scheduled task. Incidental dates, deadlines, elapsed-time estimates, and phrases such as "later" do not imply a scheduling \
            request. Ask for clarification before proposing a task when its instructions, recurrence, or target are materially ambiguous. \
            For a weekdays schedule, days must list every intended day of the week, including weekend days when \
            requested. Use propose_scheduled_task with action create to create a scheduled task. Call list_scheduled_tasks before edit, \
            pause, resume, delete, or run_now, then use propose_scheduled_task with that action. Never invent or search for a separate \
            create_scheduled_task tool. Call list_projects only when the user wants a scheduled task to run in a different Alveary Project \
            than this conversation's, and list_threads only when they want its results posted into an existing Alveary thread. \
            Pause, resume, and run_now take effect immediately. Create, edit, and delete only \
            open Alveary's native confirmation UI; describe those as opened proposals and never claim the schedule changed before \
            confirmation. Never use shell commands, crontab, launch agents, or workspace files \
            to discover or manage Alveary scheduled tasks. If these tools are unavailable, say so and direct the user to Alveary's \
            Scheduled screen instead of attempting a substitute.
            """
        )
    }

    static let tools: [AgentCLIKit.AgentHostToolDefinition] = [
        listTool,
        listProjectsTool,
        listThreadsTool,
        proposeTool
    ]
}

private extension ScheduledTaskHostToolCatalog {
    static let listProjectsTool = AgentCLIKit.AgentHostToolDefinition(
        name: listProjectsToolName,
        title: "List Alveary Projects",
        description: """
        List the Alveary Projects registered on this Mac, so a scheduled task can run in one other than this conversation's. Returns \
        each Project's name and root path. Call it only when the user wants a scheduled task to run somewhere other than where this \
        conversation runs; a scheduled task otherwise inherits this conversation's workspace. Not a directory listing, and not a \
        substitute for reading the file system.
        """,
        inputSchema: strictObject(properties: [:], required: []),
        outputSchema: strictObject(
            properties: [
                "projects": .object([
                    "type": .string("array"),
                    "items": strictObject(
                        properties: [
                            "path": stringSchema,
                            "name": stringSchema
                        ],
                        required: ["path", "name"]
                    )
                ])
            ],
            required: ["projects"]
        ),
        annotations: readOnlyAnnotations
    )

    static let listThreadsTool = AgentCLIKit.AgentHostToolDefinition(
        name: listThreadsToolName,
        title: "List threads a scheduled task can post into",
        description: """
        List the Alveary threads a scheduled task can post its results into, for propose_scheduled_task's target_thread_id. Returns \
        each thread's stable ID, name, workspace, and whether it is pinned; an unpinned thread is pinned when the user confirms the \
        proposal, so say so. Call it only when the user asks for a scheduled task's results to go into an existing thread rather than \
        a new one. Never use it to browse conversations or read their contents.
        """,
        inputSchema: strictObject(properties: [:], required: []),
        outputSchema: strictObject(
            properties: [
                "threads": .object([
                    "type": .string("array"),
                    "items": strictObject(
                        properties: [
                            "id": stringSchema,
                            "name": stringSchema,
                            "workspace": stringSchema,
                            "is_pinned": .object(["type": .string("boolean")])
                        ],
                        required: ["id", "name", "workspace", "is_pinned"]
                    )
                ])
            ],
            required: ["threads"]
        ),
        annotations: readOnlyAnnotations
    )

    static var readOnlyAnnotations: AgentCLIKit.AgentHostToolAnnotations {
        AgentCLIKit.AgentHostToolAnnotations(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    }

    static let listTool = AgentCLIKit.AgentHostToolDefinition(
        name: listToolName,
        title: "List scheduled tasks",
        description: """
        List Alveary scheduled-task definitions when the user asks what is scheduled, or before targeting an existing definition for \
        edit, pause, resume, delete, or run-now. Returns stable IDs, revisions, titles, states, and schedule summaries; it never returns \
        task prompts. Do not call for ordinary project tasks, calendar discussion, deadlines, or incidental time language.
        """,
        inputSchema: strictObject(properties: [:], required: []),
        outputSchema: strictObject(
            properties: [
                "tasks": .object([
                    "type": .string("array"),
                    "items": strictObject(
                        properties: [
                            "id": stringSchema,
                            "revision": integerSchema(minimum: 1),
                            "title": stringSchema,
                            "state": enumSchema(["active", "paused", "completed"]),
                            "schedule_summary": stringSchema
                        ],
                        required: ["id", "revision", "title", "state", "schedule_summary"]
                    )
                ])
            ],
            required: ["tasks"]
        ),
        annotations: readOnlyAnnotations
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
        send destination existing_thread with a target_thread_id from list_threads to post results into an existing thread, or a \
        workspace with a project_path from list_projects to run in a different Project. granted_roots replaces the folder grants \
        the task would otherwise inherit; entries must be absolute paths to existing folders, may combine with a project_path, and \
        every grant is shown to the user for confirmation. Provider, model, effort, permissions, and run location are bound by \
        Alveary and are intentionally not accepted. After it returns, report the `status` \
        it gave back: `applied` means the change is already in effect, and `pending_confirmation` means a proposal was opened and \
        nothing has changed yet.
        """,
        inputSchema: strictObject(
            properties: proposalProperties,
            required: ["action"]
        ),
        outputSchema: strictObject(
            properties: [
                "status": enumSchema(["pending_confirmation", "applied", "error"]),
                "proposal_id": stringSchema,
                "action": enumSchema(ScheduledTaskProposalAction.allCases.map(\.rawValue)),
                "title": stringSchema,
                "message": stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: AgentCLIKit.AgentHostToolAnnotations(
            readOnlyHint: false,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    static let proposalProperties: [String: AgentCLIKit.JSONValue] = [
        "action": enumSchema(ScheduledTaskProposalAction.allCases.map(\.rawValue)),
        "title": nonEmptyStringSchema,
        "prompt": nonEmptyStringSchema,
        "schedule": scheduleSchema,
        "task_id": nonEmptyStringSchema,
        "revision": integerSchema(minimum: 1),
        "changes": changesSchema
    ].merging(placementProperties) { current, _ in current }

    static let changesSchema: AgentCLIKit.JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "title": nonEmptyStringSchema,
            "prompt": nonEmptyStringSchema,
            "schedule": scheduleSchema
        ].merging(placementProperties) { current, _ in current }),
        "minProperties": .number(1),
        "additionalProperties": .bool(false)
    ])

    static let placementProperties: [String: AgentCLIKit.JSONValue] = [
        "destination": enumSchema(["new_thread", "existing_thread"]),
        "target_thread_id": nonEmptyStringSchema,
        "workspace": workspaceSchema
    ]

    static let workspaceSchema: AgentCLIKit.JSONValue = strictObject(
        properties: [
            "kind": enumSchema(["project", "private"]),
            "project_path": nonEmptyStringSchema,
            "granted_roots": .object([
                "type": .string("array"),
                "items": nonEmptyStringSchema,
                "uniqueItems": .bool(true)
            ])
        ],
        required: ["kind"]
    )

    static let scheduleSchema: AgentCLIKit.JSONValue = strictNestedUnionObject(
        properties: scheduleProperties,
        required: ["kind"],
        branches: [
            strictObject(
                properties: [
                    "kind": enumSchema(["once"]),
                    "at": dateTimeSchema
                ],
                required: ["kind", "at"]
            ),
            strictObject(
                properties: [
                    "kind": enumSchema(["interval"]),
                    "minutes": integerSchema(minimum: 1),
                    "anchor_at": dateTimeSchema
                ],
                required: ["kind", "minutes", "anchor_at"]
            ),
            wallClockScheduleSchema(kind: "daily"),
            strictObject(
                properties: [
                    "kind": enumSchema(["weekdays"]),
                    "days": weekdayListSchema,
                    "hour": integerSchema(minimum: 0, maximum: 23),
                    "minute": integerSchema(minimum: 0, maximum: 59)
                ],
                required: ["kind", "days", "hour", "minute"]
            ),
            strictObject(
                properties: [
                    "kind": enumSchema(["weekly"]),
                    "weekday": enumSchema(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
                    "hour": integerSchema(minimum: 0, maximum: 23),
                    "minute": integerSchema(minimum: 0, maximum: 59)
                ],
                required: ["kind", "weekday", "hour", "minute"]
            ),
            strictObject(
                properties: [
                    "kind": enumSchema(["monthly"]),
                    "day": integerSchema(minimum: 1, maximum: 31),
                    "hour": integerSchema(minimum: 0, maximum: 23),
                    "minute": integerSchema(minimum: 0, maximum: 59)
                ],
                required: ["kind", "day", "hour", "minute"]
            )
        ]
    )

    static let scheduleProperties: [String: AgentCLIKit.JSONValue] = [
        "kind": enumSchema(["once", "interval", "daily", "weekdays", "weekly", "monthly"]),
        "at": dateTimeSchema,
        "minutes": integerSchema(minimum: 1),
        "anchor_at": dateTimeSchema,
        "days": weekdayListSchema,
        "weekday": enumSchema(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
        "day": integerSchema(minimum: 1, maximum: 31),
        "hour": integerSchema(minimum: 0, maximum: 23),
        "minute": integerSchema(minimum: 0, maximum: 59)
    ]

    static func wallClockScheduleSchema(kind: String) -> AgentCLIKit.JSONValue {
        strictObject(
            properties: [
                "kind": enumSchema([kind]),
                "hour": integerSchema(minimum: 0, maximum: 23),
                "minute": integerSchema(minimum: 0, maximum: 59)
            ],
            required: ["kind", "hour", "minute"]
        )
    }

    static func strictObject(
        properties: [String: AgentCLIKit.JSONValue],
        required: [String]
    ) -> AgentCLIKit.JSONValue {
        var schema: [String: AgentCLIKit.JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(AgentCLIKit.JSONValue.string))
        }
        return .object(schema)
    }

    static func strictNestedUnionObject(
        properties: [String: AgentCLIKit.JSONValue],
        required: [String],
        branches: [AgentCLIKit.JSONValue]
    ) -> AgentCLIKit.JSONValue {
        // Keep unions nested: Claude drops tool definitions that use a union at the input-schema root.
        guard case .object(var schema) = strictObject(properties: properties, required: required) else {
            preconditionFailure("strictObject must produce an object schema")
        }
        schema["oneOf"] = .array(branches)
        return .object(schema)
    }

    static var stringSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("string")])
    }

    static var nonEmptyStringSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("string"), "minLength": .number(1)])
    }

    static var dateTimeSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("string"), "format": .string("date-time")])
    }

    static var weekdayListSchema: AgentCLIKit.JSONValue {
        .object([
            "type": .string("array"),
            "items": enumSchema(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]),
            "minItems": .number(1),
            "maxItems": .number(7),
            "uniqueItems": .bool(true)
        ])
    }

    static func enumSchema(_ values: [String]) -> AgentCLIKit.JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(AgentCLIKit.JSONValue.string))
        ])
    }

    static func integerSchema(minimum: Int, maximum: Int? = nil) -> AgentCLIKit.JSONValue {
        var schema: [String: AgentCLIKit.JSONValue] = [
            "type": .string("integer"),
            "minimum": .number(Double(minimum))
        ]
        if let maximum {
            schema["maximum"] = .number(Double(maximum))
        }
        return .object(schema)
    }
}
