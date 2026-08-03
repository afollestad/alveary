import AgentCLIKit
import Foundation
import SwiftData

/// Scheduling's read-only tool. It resolves the calling conversation first, so a caller with no
/// usable source conversation cannot read Alveary's state at all.
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
}

private extension ScheduledTaskHostToolService {
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
