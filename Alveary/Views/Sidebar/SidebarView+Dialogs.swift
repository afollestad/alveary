import SwiftUI

/// Bridges an optional "pending item" state to the `Bool` binding presentation modifiers want.
///
/// Written as a standalone generic so the dialog chain does not re-solve five inline
/// `Binding(get:set:)` closure pairs as part of a larger expression.
///
/// `@MainActor` because `Binding`'s accessors are `@Sendable` and `Binding` is not: without an
/// isolation to inherit, capturing the wrapped binding warns.
@MainActor
func sidebarPresentationBinding<Value>(for item: Binding<Value?>) -> Binding<Bool> {
    Binding(
        get: { item.wrappedValue != nil },
        set: { isPresented in
            if !isPresented {
                item.wrappedValue = nil
            }
        }
    )
}

extension SidebarView {
    /// The sidebar's confirmation dialogs and alerts, lifted out of `body`.
    ///
    /// Swift type-checks an expression as a whole, so chaining these onto the `List` made every
    /// generic `confirmationDialog(_:isPresented:presenting:actions:message:)` overload resolve
    /// together with the entire sidebar hierarchy. That pushed `body` past the compiler's
    /// per-expression time budget on slower machines, which fails the build outright rather than
    /// warning. Keeping each group in its own function keeps that cost bounded — add new
    /// presentation modifiers to a group here, and split again if a group outgrows one screen.
    func sidebarPresentationDialogs<Content: View>(_ content: Content) -> some View {
        sidebarScheduledTaskAttachmentAlert(
            sidebarSectionDialogs(
                sidebarProjectDialogs(
                    sidebarThreadLifecycleDialogs(content)
                )
            )
        )
    }

    private func sidebarThreadLifecycleDialogs<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog(
                "Archive thread?",
                isPresented: sidebarPresentationBinding(for: $pendingArchiveThread),
                presenting: pendingArchiveThread
            ) { pending in
                Button("Archive") {
                    pendingArchiveThread = nil
                    guard let thread = uiModelContext.resolveThread(id: pending.threadID) else {
                        return
                    }
                    Task { await archive(thread) }
                }

                Button("Cancel", role: .cancel) {
                    pendingArchiveThread = nil
                }
            } message: { pending in
                Text(archiveConfirmationMessage(title: pending.title))
            }
            .confirmationDialog(
                "Delete thread?",
                isPresented: sidebarPresentationBinding(for: $pendingDeleteThread),
                presenting: pendingDeleteThread
            ) { pending in
                Button("Delete", role: .destructive) {
                    pendingDeleteThread = nil
                    guard let thread = uiModelContext.resolveThread(id: pending.threadID) else {
                        return
                    }
                    Task { await confirmDeleteThread(thread) }
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteThread = nil
                }
            } message: { pending in
                Text(deleteConfirmationMessage(for: pending))
            }
    }

    private func sidebarProjectDialogs<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove project?",
                isPresented: sidebarPresentationBinding(for: $pendingDeleteProject),
                presenting: pendingDeleteProject
            ) { pending in
                Button("Remove Project", role: .destructive) {
                    pendingDeleteProject = nil
                    guard let project = uiModelContext.resolveProject(path: pending.projectPath) else {
                        return
                    }
                    Task { await confirmDeleteProject(project) }
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteProject = nil
                }
            } message: { pending in
                Text(sidebarRemoveProjectConfirmationMessage(projectName: pending.name))
            }
            .confirmationDialog(
                "Grant folder access?",
                isPresented: sidebarPresentationBinding(for: $pendingTaskProjectAccess),
                presenting: pendingTaskProjectAccess
            ) { request in
                Button("Grant Access") {
                    Task { await confirmTaskProjectAccess(request) }
                }

                Button("Cancel", role: .cancel) {
                    pendingTaskProjectAccess = nil
                }
            } message: { request in
                sidebarTaskProjectAccessConfirmationText(for: request)
            }
    }

    private func sidebarSectionDialogs<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove section?",
                isPresented: sidebarPresentationBinding(for: $pendingRemoveSection),
                presenting: pendingRemoveSection
            ) { pending in
                Button("Remove Section", role: .destructive) {
                    pendingRemoveSection = nil
                    removeSection(id: pending.id)
                }

                Button("Cancel", role: .cancel) {
                    pendingRemoveSection = nil
                }
            } message: { pending in
                Text(sidebarRemoveSectionConfirmationMessage(sectionName: pending.name))
            }
    }

    private func sidebarScheduledTaskAttachmentAlert<Content: View>(_ content: Content) -> some View {
        // The view model is held as a plain `let`, so bind it locally to reach its alert state
        // through the same optional-to-`Bool` bridge the `@State`-backed dialogs use.
        @Bindable var viewModel = viewModel

        return content
            .alert(
                "Scheduled task attachment",
                isPresented: sidebarPresentationBinding(for: $viewModel.scheduledTaskAttachmentAlert)
            ) {
                Button("OK", role: .cancel) {
                    viewModel.scheduledTaskAttachmentAlert = nil
                }
            } message: {
                Text(viewModel.scheduledTaskAttachmentAlert ?? "")
            }
    }
}

func sidebarRemoveSectionConfirmationMessage(sectionName: String) -> String {
    "Remove \(sectionName) from the sidebar? Its threads move to Tasks and are not deleted."
}

func sidebarRemoveProjectConfirmationMessage(projectName: String) -> String {
    "Remove \(projectName) from Alveary, and delete its threads and worktrees? "
        + "The main project folder will not be touched."
}
