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
    /// Precomputed rather than derived on demand, because the hover tooltip reads `worktreePath`.
    let worktreeTooltip: String
    let isPinned: Bool
    let allowsPinning: Bool
    let allowsForking: Bool

    init(thread: AgentThread) {
        let mode = thread.effectiveMode
        threadID = thread.persistentModelID
        displayName = thread.displayName()
        showsScheduledIndicator = thread.scheduledTaskRun != nil
        showsWorktreeIndicator = thread.useWorktree
        worktreeTooltip = sidebarThreadWorktreeTooltipText(for: thread)
        isPinned = thread.isPinned
        allowsPinning = mode == .task || thread.project?.isPinned != true
        allowsForking = mode == .project
    }
}
