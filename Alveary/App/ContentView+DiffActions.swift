import SwiftData
import SwiftUI

enum DiffCommitMessageGenerationRoute: Equatable {
    case thread
    case project(directory: String)
}

struct DiffGitCommitTargetSnapshot: Equatable {
    let directory: String
    let targetName: String
    let baseBranch: String
    let remoteName: String?
    let generationRoute: DiffCommitMessageGenerationRoute
}

@MainActor
enum DiffGitCommitTargetSnapshotResolver {
    static func resolve(
        selection: SidebarItem?,
        modelContext: ModelContext,
        appState: AppState,
        activeDirectory: String?
    ) -> DiffGitCommitTargetSnapshot? {
        guard let activeDirectory else {
            return nil
        }

        let snapshot: DiffGitCommitTargetSnapshot?
        switch selection {
        case .thread(let selectedThread):
            snapshot = threadSnapshot(
                for: selectedThread,
                modelContext: modelContext,
                appState: appState
            )
        case .project(let selectedProject):
            snapshot = projectSnapshot(for: selectedProject, modelContext: modelContext)
        case .skills, .mcp, .scheduled, .settings, nil:
            snapshot = nil
        }

        guard let snapshot,
              CanonicalPath.normalize(snapshot.directory) == CanonicalPath.normalize(activeDirectory) else {
            return nil
        }

        return snapshot
    }

    private static func threadSnapshot(
        for selectedThread: AgentThread,
        modelContext: ModelContext,
        appState: AppState
    ) -> DiffGitCommitTargetSnapshot? {
        guard let thread = modelContext.resolveThread(id: selectedThread.persistentModelID),
              thread.effectiveMode == .project,
              let project = thread.project else {
            return nil
        }
        if thread.isDraft {
            return projectSnapshot(for: project, modelContext: modelContext)
        }
        guard selectedConversation(in: thread, modelContext: modelContext, appState: appState) != nil else {
            return nil
        }
        let directory = thread.worktreePath ?? project.path
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return DiffGitCommitTargetSnapshot(
            directory: directory,
            targetName: thread.displayName(),
            baseBranch: project.baseRef ?? "main",
            remoteName: project.remoteName,
            generationRoute: .thread
        )
    }

    private static func projectSnapshot(
        for selectedProject: Project,
        modelContext: ModelContext
    ) -> DiffGitCommitTargetSnapshot? {
        guard let project = modelContext.resolveProject(id: selectedProject.persistentModelID) else {
            return nil
        }

        let directory = project.path
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmedName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return DiffGitCommitTargetSnapshot(
            directory: directory,
            targetName: trimmedName.isEmpty ? URL(fileURLWithPath: directory).lastPathComponent : trimmedName,
            baseBranch: project.baseRef ?? "main",
            remoteName: project.remoteName,
            generationRoute: .project(directory: directory)
        )
    }
}

extension ContentView {
    func activeDiffActionTarget() -> (thread: AgentThread, conversation: Conversation)? {
        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              let thread = uiModelContext.resolveThread(id: selectedThread.persistentModelID),
              thread.effectiveMode == .project,
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
            activeDirectory: diffViewModel.activeDirectory
        )
    }

    func presentGitCommitModal() {
        guard let target = activeDiffCommitTargetSnapshot() else {
            return
        }

        let context = DiffGitCommitModalContext(
            directory: target.directory,
            targetName: target.targetName,
            baseBranch: target.baseBranch,
            remoteName: target.remoteName
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

    func requestCommitMessageGeneration(
        prompt: String,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        guard let (_, conversation) = activeDiffActionTarget() else {
            completion(.failure(CommitMessageGenerationError.activeConversationChanged))
            return
        }

        appState.requestCommitMessageGeneration(
            prompt: prompt,
            conversationID: conversation.persistentModelID,
            completion: completion
        )
    }

    func generateCommitMessage(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            requestCommitMessageGeneration(prompt: prompt) { result in
                continuation.resume(with: result)
            }
        }
    }

    func generateCommitMessage(prompt: String, route: DiffCommitMessageGenerationRoute) async throws -> String {
        switch route {
        case .thread:
            return try await generateCommitMessage(prompt: prompt)
        case .project(let directory):
            return try await agentOneShotPromptService.generate(prompt: prompt, workingDirectory: directory)
        }
    }

    func cancelPendingCommitMessageGenerationIfNeeded() {
        guard let request = appState.pendingCommitMessageGenerationRequest else {
            return
        }

        guard let activeConversationID = activeDiffActionTarget()?.conversation.persistentModelID,
              activeConversationID == request.conversationID else {
            appState.cancelPendingCommitMessageGenerationRequest()
            return
        }
    }
}
