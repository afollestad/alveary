import SwiftData
import SwiftUI

struct SidebarTaskProjectAccessDrop: Equatable {
    let threadID: PersistentIdentifier
    let projectID: PersistentIdentifier
}

/// Recognizes the one drop shape that grants folder access instead of reordering. Kept pure so the
/// routing decision is testable without driving a live drag.
func sidebarTaskProjectAccessDrop(
    item: SidebarDragItem,
    target: SidebarDropTarget
) -> SidebarTaskProjectAccessDrop? {
    guard target.placement == .into,
          case .project(let projectID) = target.item else {
        return nil
    }
    switch item {
    case .pinnedTask(let threadID), .unpinnedTask(let threadID):
        return SidebarTaskProjectAccessDrop(threadID: threadID, projectID: projectID)
    case .project, .pinnedThread:
        return nil
    }
}

extension SidebarView {
    /// Validates synchronously at drop time so an ineligible Task explains itself immediately
    /// rather than opening a dialog that would fail on confirm.
    func requestTaskProjectAccessDrop(threadID: PersistentIdentifier, projectID: PersistentIdentifier) {
        do {
            let request = try viewModel.validateTaskProjectAccess(
                threadID: threadID,
                projectID: projectID
            )
            // Confirmation exists to authorize new folder access. When the Task can already reach
            // the folder the drop is pure placement — non-destructive and undone by dragging back
            // out — so asking would be noise.
            guard request.grantsNewAccess else {
                Task { await confirmTaskProjectAccess(request) }
                return
            }
            pendingTaskProjectAccess = request
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func confirmTaskProjectAccess(_ request: SidebarTaskProjectAccessRequest) async {
        pendingTaskProjectAccess = nil
        do {
            try await viewModel.moveTaskIntoProject(request.threadID, projectID: request.projectID)
        } catch {
            viewModel.presentSidebarError(error)
            return
        }
        // A blocking modal can appear while the move awaits; do not reveal rows underneath it.
        guard voiceInputLifecycleController?.isModelPreparationModalPresented != true else {
            return
        }
        // The Task now lives in this project, so a collapsed project would otherwise swallow it.
        expandedProjects.insert(request.projectPath)
    }
}

/// The confirmation message broken into its styled parts. Emphasis is applied by interpolating
/// `Text` values, never by parsing Markdown, so a project or thread name containing Markdown
/// characters cannot inject its own formatting.
struct SidebarTaskProjectAccessMessage: Equatable {
    let leading: String
    let quotedThreadName: String
    let middle: String
    let projectName: String
    let trailing: String
    let detail: String
}

func sidebarTaskProjectAccessConfirmationMessage(
    for request: SidebarTaskProjectAccessRequest
) -> SidebarTaskProjectAccessMessage {
    SidebarTaskProjectAccessMessage(
        leading: "Moves ",
        quotedThreadName: "\"\(request.threadName)\"",
        middle: " into ",
        projectName: request.projectName,
        trailing: " and gives the agent access to that project folder.\n\n",
        detail: "The task stays a task and keeps its own workspace"
            + (request.restartsAgentProcess
                ? ", and its conversation continues where it left off."
                : ".")
    )
}

/// Interpolated `Text` rather than an `AttributedString`, because `.bold()`/`.italic()` adjust the
/// inherited dialog font instead of replacing it with a hardcoded size.
///
/// The interpolation must stay a single string literal. Concatenating literals with `+` makes the
/// argument a plain `String` expression, which resolves to `Text(String)` and renders each nested
/// `Text` as its debug description instead of styled text.
func sidebarTaskProjectAccessConfirmationText(
    for request: SidebarTaskProjectAccessRequest
) -> Text {
    let message = sidebarTaskProjectAccessConfirmationMessage(for: request)
    let thread = Text(verbatim: message.quotedThreadName).bold()
    let project = Text(verbatim: message.projectName).bold()
    let detail = Text(verbatim: message.detail).italic()
    return Text("\(message.leading)\(thread)\(message.middle)\(project)\(message.trailing)\(detail)")
}
