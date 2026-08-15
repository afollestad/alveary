import AgentCLIKit
import Foundation
import SwiftData

/// The read-only thread tools. Each resolves the calling conversation first, so a caller Alveary
/// cannot place reads nothing.
extension ThreadHostToolService {
    /// Lists the user's active threads and their settings.
    ///
    /// Thread names are user content, so this is where Alveary hands conversation-derived titles
    /// to the provider; the tool description restricts it to identifying a thread. It exposes no
    /// transcript content, and unlistable threads are omitted entirely rather than reported as
    /// unavailable, so nothing leaks about archived or forked work.
    func listThreads(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try requireNoArguments(arguments, toolName: ThreadHostToolCatalog.listThreadsToolName)
        let source = try resolveSource(context: context)
        let listings = try fetchAll(AgentThread.self)
            .compactMap { thread -> ThreadHostToolListing? in
                guard thread.isListableHostToolThread,
                      let conversation = thread.soleMainConversation else {
                    return nil
                }
                return ThreadHostToolListing(
                    thread: thread,
                    conversation: conversation,
                    isCurrent: conversation.id == source.conversation.id
                )
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

        return AgentCLIKit.AgentHostToolResult(
            text: listText(
                header: "Found \(count(listings.count, singular: "thread"))",
                rows: listings.map(\.textRow)
            ),
            structuredContent: .object(["threads": .array(listings.map(\.structuredRow))])
        )
    }

    func listProjects(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try requireNoArguments(arguments, toolName: ThreadHostToolCatalog.listProjectsToolName)
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
}

/// One `list_threads` row, rendered identically into `structuredContent` and the text fallback.
private struct ThreadHostToolListing {
    let thread: AgentThread
    let conversation: Conversation
    let isCurrent: Bool

    var structuredRow: AgentCLIKit.JSONValue {
        var row: [String: AgentCLIKit.JSONValue] = [
            "id": .string(conversation.id),
            "name": .string(thread.displayName()),
            "workspace": .string(workspaceSummary),
            "workspace_kind": .string(thread.effectiveMode.rawValue),
            "provider": .string(conversation.provider ?? "unknown"),
            "model": .string(thread.model ?? AppSettings.defaultModelValue),
            "effort": .string(thread.effort),
            "permission_mode": .string(thread.permissionMode),
            "is_pinned": .bool(thread.isPinned),
            "is_current": .bool(isCurrent)
        ]
        if let sectionName {
            row["section"] = .string(sectionName)
        }
        if let projectPath = thread.project?.path {
            row["project_path"] = .string(projectPath)
        }
        if let modifiedAt = thread.modifiedAt {
            row["modified_at"] = .string(ThreadHostToolDates.canonical(modifiedAt))
        }
        return .object(row)
    }

    var textRow: String {
        var parts = [
            "id: \(conversation.id)",
            workspaceSummary,
            conversation.provider ?? "unknown",
            "model \(thread.model ?? AppSettings.defaultModelValue)",
            "effort \(thread.effort)",
            "permissions \(thread.permissionMode)",
            thread.isPinned ? "pinned" : "unpinned"
        ]
        if let sectionName {
            parts.append("section \(sectionName)")
        }
        if isCurrent {
            parts.append("this conversation's thread")
        }
        return "- \"\(thread.displayName())\" (\(parts.joined(separator: ", ")))"
    }

    /// The sidebar section this thread belongs to — where it renders, or returns to on unpin
    /// when `is_pinned` says it currently sits under `Pinned`. Nil for a Project-placed thread,
    /// which renders under its Project rather than in any section.
    private var sectionName: String? {
        guard thread.project == nil, thread.effectiveMode == .task else {
            return nil
        }
        return thread.customSection?.name
            ?? SidebarSectionKind.tasks.builtinDisplayName
    }

    private var workspaceSummary: String {
        switch thread.effectiveMode {
        case .project:
            "project: \(thread.project?.name ?? "unknown")"
        case .task:
            "task"
        }
    }
}
