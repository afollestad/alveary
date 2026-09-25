import SwiftUI

extension View {
    /// The address-feedback route refuses outright when no project holds the pull request's
    /// repository — it edits and pushes, so a thread with no checkout could not do the job. A modal
    /// rather than a banner because the fix is elsewhere in the app, and dismissing is the only thing
    /// to do here. Shared by the pane and the list screen, whose row menu starts routes with no pane.
    func pullRequestMissingProjectAlert(
        repository: String?,
        onDismiss: @escaping @MainActor () -> Void
    ) -> some View {
        alert(
            "Project not added",
            isPresented: Binding(
                get: { repository != nil },
                set: { isPresented in
                    if !isPresented {
                        onDismiss()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel, action: onDismiss)
        } message: {
            Text(missingProjectMessage(repository: repository))
        }
    }
}

/// Rebuilt from the error rather than respelled here, so the sentence has one author.
private func missingProjectMessage(repository: String?) -> String {
    guard let repository else {
        return ""
    }
    return PullRequestAgenticThreadService.StartError
        .projectMissing(repository: repository)
        .localizedDescription
}
