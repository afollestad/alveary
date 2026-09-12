import SwiftData
import SwiftUI

/// The Git changes pane footer's create-pull-request flow: presenting the
/// modal, then automatically linking the created pull request to the selection
/// and opening its pane over the still-requested Diff Viewer.
extension ContentView {
    /// Renders the third root `.sheet` from its own type-check scope; see the
    /// type-check budget rule in `Alveary/Views/AGENTS.md`.
    func createPullRequestSheetHost<Content: View>(_ content: Content) -> some View {
        content.sheet(item: $createPullRequestModalModel) { model in
            DiffCreatePullRequestModal(
                model: model,
                onCreated: { identifier in
                    handleCreatedPullRequest(
                        identifier, owner: model.context.owner, directory: model.context.directory,
                        sourceDirectory: model.context.sourceDirectory
                    )
                },
                onClose: { createPullRequestModalModel = nil }
            )
        }
    }

    func presentCreatePullRequestModal() {
        guard let target = activeDiffCommitTargetSnapshot(),
              let owner = selectedPullRequestLinkOwner else {
            return
        }

        guard requireSelectedWorkspaceDirectory() else { return }
        createPullRequestModalModel = DiffCreatePullRequestModalModel(
            context: DiffCreatePullRequestModalContext(
                directory: target.directory,
                targetName: target.targetName,
                baseBranch: target.baseBranch,
                remoteName: target.remoteName,
                owner: owner,
                sourceDirectory: target.sourceDirectory
            ),
            gitService: gitService,
            pullRequestsService: pullRequestsViewModel.service,
            settingsService: settingsService,
            generateText: { prompt in
                // The same hidden-generation channel the commit modal uses; the
                // route decides between the thread's conversation and a one-shot.
                try await generateCommitMessage(prompt: prompt, route: target.generationRoute)
            },
            refreshAfterMutation: {
                await diffViewModel.refreshAndInvalidateFileList(in: target.directory, reason: .localGitMutation)
            }
        )
    }

    /// Links the created pull request to its owner — no URL paste, no prompt —
    /// then opens its pane preserving the Diff Viewer request, so the pane's X
    /// brings the Git changes pane back and its footer already reads View PR.
    func handleCreatedPullRequest(
        _ identifier: PullRequestIdentifier, owner: PullRequestLinkOwner, directory: String, sourceDirectory: String? = nil
    ) {
        let sourceDirectory = sourceDirectory ?? directory
        createPullRequestModalModel = nil
        Task {
            await pullRequestLinksViewModel.link(identifier, owner: owner)
            // Only open over the selection the flow started from; a changed
            // selection keeps the link but stays where the user went.
            guard selectedPullRequestLinkOwner == owner, selectedWorkspaceFolder?.directory == sourceDirectory else { return }
            guard let row = selectedPullRequestLinks.first(where: { $0.id == identifier }) else {
                // The create succeeded but the validating link fetch failed;
                // the pull request exists on GitHub, so say what happened
                // rather than silently doing nothing.
                appState.presentUnexpectedError(
                    message: pullRequestLinksViewModel.linkErrorMessage
                        ?? "The pull request was created, but linking it failed."
                )
                return
            }
            await refreshSelectedFolderRepository()
            guard selectedPullRequestLinkOwner == owner, selectedWorkspaceFolder?.directory == sourceDirectory,
                  selectedFolderPullRequestLinks.contains(where: { $0.id == identifier }) else { return }
            openLinkedPullRequest(row, preservingDiffViewer: true)
        }
    }

    /// The footer's View PR action: exactly one linked pull request, opened
    /// over the still-requested Diff Viewer so closing it comes back here.
    func openSinglePullRequestFromDiffFooter() {
        let rows = selectedFolderPullRequestLinks
        guard rows.count == 1, let row = rows.first else {
            return
        }
        openLinkedPullRequest(row, preservingDiffViewer: true)
    }
}
