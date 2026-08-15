import Foundation
import SwiftData

/// Everything `SidebarThreadRow` renders, plus what its context menu offers, snapshotted off the
/// live `AgentThread` while the parent body still holds one.
///
/// The row re-runs `body` from its *own* `@State` — hover, and the cleanup pill's 180ms collapse
/// task — with no parent rebuild in between. Both can fire after a delete has committed and while
/// `List` is still animating the row out, and a persisted-property read there traps inside
/// SwiftData with `_assertionFailure`. Value types cannot, so the row never stores a model.
///
/// The context-menu fields are here for the same reason: `.contextMenu`'s content closure is
/// evaluated lazily when the menu opens, not when the row is built.
struct SidebarThreadRowPresentation: Equatable {
    let threadID: PersistentIdentifier
    let displayName: String
    let showsScheduledIndicator: Bool
    let showsWorktreeIndicator: Bool
    /// Raw persisted worktree path, trimmed; `nil` when the thread has none yet. Stored raw so the
    /// hover tooltip still never reads the model, but deliberately not canonicalized here:
    /// `sidebarThreadWorktreeTooltipText(worktreePath:)` stats every path component, a cost the
    /// parent must not pay while building every visible row's presentation each body pass.
    let worktreePath: String?
    let isPinned: Bool
    let allowsPinning: Bool
    let allowsForking: Bool

    init(thread: AgentThread) {
        let mode = thread.effectiveMode
        threadID = thread.persistentModelID
        displayName = thread.displayName()
        showsScheduledIndicator = thread.scheduledTaskRun != nil
        showsWorktreeIndicator = thread.useWorktree
        let trimmedWorktreePath = thread.worktreePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        worktreePath = trimmedWorktreePath.flatMap { $0.isEmpty ? nil : $0 }
        isPinned = thread.isPinned
        allowsPinning = mode == .task || thread.project?.isPinned != true
        allowsForking = mode == .project
    }
}
