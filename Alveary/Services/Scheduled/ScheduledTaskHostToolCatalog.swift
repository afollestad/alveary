import AgentCLIKit
import Foundation

enum ScheduledTaskHostToolCatalog {
    static let listToolName = "list_scheduled_tasks"
    static let proposeToolName = "propose_scheduled_task"

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
            create_scheduled_task tool. A proposal only opens Alveary's native confirmation UI; describe it as an opened proposal and \
            never claim the schedule changed before confirmation. Never use shell commands, crontab, launch agents, or workspace files \
            to discover or manage Alveary scheduled tasks. If these tools are unavailable, say so and direct the user to Alveary's \
            Scheduled screen instead of attempting a substitute.
            """
        )
    }

    static let tools: [AgentCLIKit.AgentHostToolDefinition] = [listTool, proposeTool]
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
        annotations: AgentCLIKit.AgentHostToolAnnotations(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    static let proposeTool = AgentCLIKit.AgentHostToolDefinition(
        name: proposeToolName,
        title: "Propose a scheduled task change",
        description: """
        Create, edit, pause, resume, delete, or run now an Alveary scheduled task by opening a native confirmation proposal after the user \
        explicitly requests that action. Use action create for a new scheduled task; there is no separate create_scheduled_task tool. For \
        create, provide title, prompt, and schedule. For edit, provide task_id, revision, and changes. For pause, resume, delete, or run_now, \
        provide task_id and revision. For existing definitions, call list_scheduled_tasks first and pass its exact task_id and revision. Ask \
        for clarification instead of guessing materially ambiguous instructions, recurrence, or target. Edit changes may replace \
        title, prompt, or the complete schedule. Provider, model, permissions, workspace, Project, authorization, and folder grants are bound \
        by Alveary and are intentionally not accepted. This tool never changes a canonical schedule by itself. After it returns, say that a \
        proposal was opened for confirmation.
        """,
        inputSchema: strictObject(
            properties: proposalProperties,
            required: ["action"]
        ),
        outputSchema: strictObject(
            properties: [
                "status": enumSchema(["pending_confirmation", "error"]),
                "proposal_id": stringSchema,
                "action": enumSchema(ScheduledTaskProposalAction.allCases.map(\.rawValue)),
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
    ]

    static let changesSchema: AgentCLIKit.JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "title": nonEmptyStringSchema,
            "prompt": nonEmptyStringSchema,
            "schedule": scheduleSchema
        ]),
        "minProperties": .number(1),
        "additionalProperties": .bool(false)
    ])

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
