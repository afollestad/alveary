import Foundation

enum ThreadHostToolPresentation {
    /// The Projects lookup renders with the sidebar's folder icon, not the thread bubble.
    static func isListProjectsTool(named toolName: String) -> Bool {
        matches(toolName, hostToolName: ThreadHostToolCatalog.listProjectsToolName)
    }

    /// Any Alveary thread-management host tool, for shared row chrome such as the bubble icon.
    /// Derived from the catalog minus the Projects lookup, so a new thread tool cannot be added
    /// without its row picking up the same glyph.
    static func isThreadTool(named toolName: String) -> Bool {
        ThreadHostToolCatalog.tools
            .map(\.name)
            .filter { $0 != ThreadHostToolCatalog.listProjectsToolName }
            .contains { matches(toolName, hostToolName: $0) }
    }

    /// Providers disagree on whether a host tool name carries the server prefix.
    private static func matches(_ toolName: String, hostToolName: String) -> Bool {
        AlvearyHostToolCatalog.matches(reportedName: toolName, hostToolName: hostToolName)
    }
}
