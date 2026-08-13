import Foundation
import SwiftData

/// The row a sidebar archive/delete confirmation is armed against, captured as values.
///
/// A `confirmationDialog`'s `message:` closure re-evaluates on every host body pass for as long as
/// the dialog stays armed, so a `@Model` held here would let the message read a row that a delete
/// committed in the meantime and trap inside SwiftData. The dialog's destructive button
/// re-resolves `threadID` instead; a `nil` resolve means already gone.
struct SidebarPendingThreadCleanup: Equatable {
    let threadID: PersistentIdentifier
    let title: String
    let isTask: Bool

    init(thread: AgentThread) {
        threadID = thread.persistentModelID
        title = thread.displayName()
        isTask = thread.effectiveMode == .task
    }
}

/// The project a sidebar removal confirmation is armed against. Keyed by path rather than
/// `PersistentIdentifier` because every project route in the sidebar already resolves by path.
struct SidebarPendingProjectRemoval: Equatable {
    let projectPath: String
    let name: String

    init(project: Project) {
        projectPath = project.path
        name = project.name
    }
}
