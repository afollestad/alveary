import Foundation

enum PullRequestHostToolPresentation {
    /// Every host tool whose subject is a pull request, so its transcript row carries the same
    /// octicon the sidebar row and toolbar button use.
    ///
    /// This spans two features on purpose: the pull request tools plus the threads feature's
    /// `link_pr` / `unlink_pr` / `list_linked_prs`, which manage Alveary's own links but are still
    /// about a pull request. Derived from both catalogs so a new tool in either cannot be added
    /// without its row picking up the right glyph.
    static func isPullRequestTool(named toolName: String) -> Bool {
        pullRequestToolNames.contains { matches(toolName, hostToolName: $0) }
    }

    private static let pullRequestToolNames: [String] =
        PullRequestHostToolCatalog.tools.map(\.name) + [
            ThreadHostToolCatalog.linkPullRequestToolName,
            ThreadHostToolCatalog.unlinkPullRequestToolName,
            ThreadHostToolCatalog.listPullRequestsToolName
        ]

    /// Providers disagree on whether a host tool name carries the server prefix.
    private static func matches(_ toolName: String, hostToolName: String) -> Bool {
        AlvearyHostToolCatalog.matches(reportedName: toolName, hostToolName: hostToolName)
    }
}
