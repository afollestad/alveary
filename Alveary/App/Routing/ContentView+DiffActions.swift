import SwiftData
import SwiftUI

enum DiffCommitMessageGenerationRoute: Equatable {
    case thread(threadID: PersistentIdentifier, conversationID: PersistentIdentifier)
    case project(directory: String)
}

struct DiffGitCommitTargetSnapshot: Equatable {
    let directory: String
    let sourceDirectory: String
    let targetName: String
    let baseBranch: String
    let remoteName: String?
    let generationRoute: DiffCommitMessageGenerationRoute
}

@MainActor
enum DiffGitCommitTargetSnapshotResolver {
    static func resolve(
        selection: SidebarItem?, modelContext: ModelContext, appState: AppState,
        activeDirectory: String?, activeSourceDirectory: String? = nil,
        folderSelection: WorkspaceFolderSelection = WorkspaceFolderSelection()
    ) -> DiffGitCommitTargetSnapshot? {
        guard let activeDirectory else { return nil }
        let folder: WorkspaceFolderTarget?
        let name: String
        var generationRoute = DiffCommitMessageGenerationRoute.project(directory: activeDirectory)
        switch selection?.resolved(in: modelContext) {
        case .thread(let thread) where thread.archivedAt == nil:
            folder = folderSelection.selected(in: thread.workspaceFolderTargets, owner: .thread(thread.persistentModelID))
            name = thread.displayName()
            if folder?.isPrimary == true, !thread.isDraft,
               let conversation = selectedConversation(in: thread, modelContext: modelContext, appState: appState) {
                generationRoute = .thread(threadID: thread.persistentModelID, conversationID: conversation.persistentModelID)
            }
        case .project(let project):
            folder = folderSelection.selected(in: project.workspaceFolderTargets, owner: .project(project.id))
            name = project.name
        default:
            return nil
        }
        guard let folder, folder.directory == (activeSourceDirectory ?? activeDirectory) else { return nil }
        return DiffGitCommitTargetSnapshot(
            directory: activeDirectory,
            sourceDirectory: folder.directory,
            targetName: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folder.source.name : name,
            baseBranch: folder.baseRef ?? "main", remoteName: folder.remoteName, generationRoute: generationRoute
        )
    }
}

extension ContentView {
    func activeDiffActionTarget() -> (thread: AgentThread, conversation: Conversation)? {
        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              let thread = uiModelContext.resolveThread(id: selectedThread.persistentModelID),
              !thread.isDraft,
              let conversation = selectedConversation(in: thread, modelContext: uiModelContext, appState: appState) else {
            return nil
        }

        return (thread, conversation)
    }

    func activeDiffCommitTargetSnapshot() -> DiffGitCommitTargetSnapshot? {
        DiffGitCommitTargetSnapshotResolver.resolve(
            selection: appState.selectedSidebarItem,
            modelContext: uiModelContext,
            appState: appState,
            activeDirectory: diffViewModel.activeDirectory,
            activeSourceDirectory: diffViewModel.activeSourceDirectory,
            folderSelection: folderSelection
        )
    }

    func requireSelectedWorkspaceDirectory() -> Bool {
        guard let folder = selectedWorkspaceFolder else { return false }
        do {
            _ = try folder.requireDirectory()
            return true
        } catch {
            appState.presentUnexpectedError(message: error.localizedDescription)
            return false
        }
    }

    func presentGitCommitModal() {
        guard let target = activeDiffCommitTargetSnapshot() else {
            return
        }

        guard requireSelectedWorkspaceDirectory() else { return }
        let context = DiffGitCommitModalContext(
            directory: target.directory,
            targetName: target.targetName,
            baseBranch: target.baseBranch,
            remoteName: target.remoteName,
            sourceDirectory: target.sourceDirectory
        )

        gitCommitModalModel = DiffGitCommitModalModel(
            context: context,
            gitService: gitService,
            settingsService: settingsService,
            generateCommitMessage: { prompt in
                try await generateCommitMessage(prompt: prompt, route: target.generationRoute)
            },
            refreshAfterMutation: {
                await diffViewModel.refreshAndInvalidateFileList(in: target.directory, reason: .localGitMutation)
            }
        )
    }

    func generateCommitMessage(prompt: String, route: DiffCommitMessageGenerationRoute) async throws -> String {
        switch route {
        case .thread(let threadID, let conversationID):
            guard let (thread, conversation) = activeDiffActionTarget(),
                  thread.persistentModelID == threadID, conversation.persistentModelID == conversationID else {
                throw CommitMessageGenerationError.activeConversationChanged
            }
            return try await withCheckedThrowingContinuation { continuation in
                appState.requestCommitMessageGeneration(
                    prompt: prompt, threadID: threadID, conversationID: conversationID
                ) { continuation.resume(with: $0) }
            }
        case .project(let directory):
            return try await agentOneShotPromptService.generate(prompt: prompt, workingDirectory: directory)
        }
    }
}
