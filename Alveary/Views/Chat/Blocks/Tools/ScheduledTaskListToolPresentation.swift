import Foundation

/// Live scheduled-task data and actions a tool row's expanded detail renders.
///
/// The list tool's own result cannot supply this: it is a snapshot, and providers that
/// surface only the text fallback carry no rows at all. Alveary owns the definitions, so
/// the row reads them directly and always shows current state.
struct ScheduledTaskListToolActions {
    var rows: @MainActor () -> [ScheduledTaskListRow] = { [] }
    var onEdit: @MainActor (String) -> Void = { _ in }
}

struct ScheduledTaskListRow: Equatable, Identifiable {
    let id: String
    let title: String
    let state: ScheduledTaskState
    let scheduleSummary: String
    /// A run is currently in flight; the run-now widget reads its tense from this.
    var hasActiveRun = false
}

enum ScheduledTaskListToolPresentation {
    /// Providers disagree on whether a host tool name carries the server prefix.
    static func isListTool(named toolName: String) -> Bool {
        matches(toolName, hostToolName: ScheduledTaskHostToolCatalog.listToolName)
    }

    /// Any Alveary scheduling host tool, for shared row chrome such as the clock icon.
    static func isSchedulingTool(named toolName: String) -> Bool {
        isListTool(named: toolName)
            || matches(toolName, hostToolName: ScheduledTaskHostToolCatalog.proposeToolName)
    }

    private static func matches(_ toolName: String, hostToolName: String) -> Bool {
        AlvearyHostToolCatalog.matches(reportedName: toolName, hostToolName: hostToolName)
    }
}
