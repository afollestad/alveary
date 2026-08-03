import AgentCLIKit
import Foundation
import SwiftData

/// The read-only `alveary_host` tools. Each one resolves the calling conversation first, so a
/// caller with no usable source conversation cannot read Alveary's state at all.
extension ScheduledTaskHostToolService {
    func listScheduledTasks(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try requireNoArguments(arguments, toolName: ScheduledTaskHostToolCatalog.listToolName)
        _ = try resolveSource(context: context)
        let definitions = try fetchAll(
            ScheduledTask.self,
            sortBy: [
                SortDescriptor(\ScheduledTask.createdAt),
                SortDescriptor(\ScheduledTask.id)
            ]
        )

        let tasks = definitions.map { definition in
            AgentCLIKit.JSONValue.object([
                "id": .string(definition.id),
                "revision": .number(Double(definition.revision)),
                "title": .string(definition.title),
                "state": .string(definition.state.rawValue),
                "schedule_summary": .string(ScheduledTaskHostToolSupport.scheduleSummary(
                    for: definition,
                    timeZoneIdentifier: currentTimeZone().identifier
                ))
            ])
        }
        return AgentCLIKit.AgentHostToolResult(
            text: listText(
                header: "Found \(count(definitions.count, singular: "scheduled task"))",
                rows: definitions.map { definition in
                    let summary = ScheduledTaskHostToolSupport.scheduleSummary(
                        for: definition,
                        timeZoneIdentifier: currentTimeZone().identifier
                    )
                    return "- \"\(definition.title)\" (id: \(definition.id), revision \(definition.revision), " +
                        "\(definition.state.rawValue), \(summary))"
                }
            ),
            structuredContent: .object(["tasks": .array(tasks)])
        )
    }

    func listProjects(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try requireNoArguments(arguments, toolName: ScheduledTaskHostToolCatalog.listProjectsToolName)
        _ = try resolveSource(context: context)
        let projects = try fetchAll(Project.self, sortBy: [SortDescriptor(\Project.path)])

        let rows = projects.map { project in
            AgentCLIKit.JSONValue.object([
                "path": .string(project.path),
                "name": .string(project.name)
            ])
        }
        return AgentCLIKit.AgentHostToolResult(
            text: listText(
                header: "Found \(count(projects.count, singular: "Project"))",
                rows: projects.map { "- \($0.name) (\($0.path))" }
            ),
            structuredContent: .object(["projects": .array(rows)])
        )
    }

    /// Lists candidate `destination: existing_thread` targets.
    ///
    /// Names are user content, so this is the one tool that hands conversation titles to the
    /// provider; its description restricts it to existing-thread targeting. It exposes no
    /// transcript content, and ineligible threads are omitted entirely rather than returned as
    /// unavailable, so nothing leaks about archived or forked work.
    func listThreads(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try requireNoArguments(arguments, toolName: ScheduledTaskHostToolCatalog.listThreadsToolName)
        _ = try resolveSource(context: context)
        let targets = try fetchAll(AgentThread.self)
            .compactMap { thread -> (thread: AgentThread, conversation: Conversation)? in
                guard thread.isEligibleScheduledTaskTarget,
                      let conversation = thread.soleMainConversation else {
                    return nil
                }
                return (thread, conversation)
            }
            // Most recently touched first, because that is what "that thread" usually means;
            // the conversation id breaks ties so repeated calls agree.
            .sorted { lhs, rhs in
                let lhsDate = lhs.thread.modifiedAt ?? .distantPast
                let rhsDate = rhs.thread.modifiedAt ?? .distantPast
                guard lhsDate == rhsDate else {
                    return lhsDate > rhsDate
                }
                return lhs.conversation.id < rhs.conversation.id
            }

        let rows = targets.map { target in
            AgentCLIKit.JSONValue.object([
                "id": .string(target.conversation.id),
                "name": .string(target.thread.displayName()),
                "workspace": .string(Self.workspaceSummary(for: target.thread)),
                "is_pinned": .bool(target.thread.isPinned)
            ])
        }
        return AgentCLIKit.AgentHostToolResult(
            text: listText(
                header: "Found \(count(targets.count, singular: "thread"))",
                rows: targets.map { target in
                    "- \"\(target.thread.displayName())\" (id: \(target.conversation.id), " +
                        "\(Self.workspaceSummary(for: target.thread)), " +
                        "\(target.thread.isPinned ? "pinned" : "unpinned"))"
                }
            ),
            structuredContent: .object(["threads": .array(rows)])
        )
    }
}

private extension ScheduledTaskHostToolService {
    static func workspaceSummary(for thread: AgentThread) -> String {
        switch thread.effectiveMode {
        case .project:
            "project: \(thread.project?.name ?? "unknown")"
        case .task:
            "task"
        }
    }

    func requireNoArguments(
        _ arguments: [String: AgentCLIKit.JSONValue],
        toolName: String
    ) throws {
        guard arguments.isEmpty else {
            throw ScheduledTaskHostToolServiceError.listDoesNotAcceptArguments(toolName: toolName)
        }
    }

    func fetchAll<Model: PersistentModel>(
        _ type: Model.Type,
        sortBy: [SortDescriptor<Model>] = []
    ) throws -> [Model] {
        do {
            return try modelContext.fetch(FetchDescriptor<Model>(sortBy: sortBy))
        } catch {
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
    }

    func count(_ value: Int, singular: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(singular)s"
    }

    /// The rows go into the text as well as `structuredContent`: a plain-text-fallback provider
    /// sees only the text, and the transcript's Output section shows the same string.
    func listText(header: String, rows: [String]) -> String {
        rows.isEmpty ? "\(header)." : "\(header):\n\(rows.joined(separator: "\n"))"
    }
}
