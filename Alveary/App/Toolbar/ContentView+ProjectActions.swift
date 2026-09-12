import SwiftData
import SwiftUI

struct ProjectActionExecutionContext: Equatable {
    let title: String
    /// Nil for an action run from a project row or a draft thread — the terminal
    /// session is project-scoped and belongs to no thread.
    let threadID: PersistentIdentifier?
    let threadName: String?
    let currentDirectory: String
    let command: String

    init(folder: WorkspaceFolderTarget, thread: AgentThread?, action: AlvearyProjectConfig.ProjectAction) {
        title = action.name
        threadID = thread?.isDraft == false ? thread?.persistentModelID : nil
        threadName = threadID == nil ? nil : thread?.name
        currentDirectory = folder.directory
        command = action.command
    }
}

enum ProjectActionTerminalPresentation {
    static func shouldAutoExpand(settings: AppSettings) -> Bool {
        settings.expandTerminalWhenActionsRun
    }

    static func maxSessions(settings: AppSettings) -> Int {
        settings.maxTerminalSessions
    }
}

struct TerminalDefaultShellContext: Equatable {
    var title = "Shell"
    var threadID: PersistentIdentifier?
    var threadName: String?
    var currentDirectory: String
}

@MainActor
enum TerminalDefaultShellContextResolver {
    static func resolve(
        selection: SidebarItem?,
        modelContext: ModelContext,
        builder: TerminalLaunchBuilder = TerminalLaunchBuilder()
    ) -> TerminalDefaultShellContext {
        switch selection {
        case .thread(let selectedThread):
            guard let thread = modelContext.resolveThread(id: selectedThread.persistentModelID),
                  thread.archivedAt == nil else {
                return fallback(builder: builder)
            }

            if thread.isDraft {
                let draftDirectory = thread.primaryWorkingDirectory
                return TerminalDefaultShellContext(
                    currentDirectory: builder.defaultShellDirectory(
                        threadWorktreePath: nil,
                        threadProjectPath: nil,
                        selectedProjectPath: draftDirectory
                    )
                )
            }

            return TerminalDefaultShellContext(
                threadID: thread.persistentModelID,
                threadName: thread.name,
                currentDirectory: builder.defaultShellDirectory(
                    threadWorktreePath: thread.effectiveMode == .project ? thread.worktreePath : nil,
                    threadProjectPath: thread.primaryWorkingDirectory,
                    selectedProjectPath: nil
                )
            )
        case .project(let selectedProject):
            let projectPath = modelContext.resolveProject(id: selectedProject.persistentModelID)?.primaryFolder?.path
            return TerminalDefaultShellContext(
                currentDirectory: builder.defaultShellDirectory(
                    threadWorktreePath: nil,
                    threadProjectPath: nil,
                    selectedProjectPath: projectPath
                )
            )
        case .skills, .mcp, .scheduled, .pullRequests, .archived, .settings, nil:
            return fallback(builder: builder)
        }
    }

    private static func fallback(builder: TerminalLaunchBuilder) -> TerminalDefaultShellContext {
        TerminalDefaultShellContext(
            currentDirectory: builder.defaultShellDirectory(
                threadWorktreePath: nil,
                threadProjectPath: nil,
                selectedProjectPath: nil
            )
        )
    }
}

extension ContentView {
    func runProjectAction(owner: ToolbarProjectActionsOwner, action: AlvearyProjectConfig.ProjectAction) {
        guard let context = resolvedProjectActionExecutionContext(owner: owner, action: action) else {
            return
        }

        let settings = settingsService.current
        let launchConfiguration = TerminalLaunchBuilder().projectAction(
            command: context.command,
            currentDirectory: context.currentDirectory
        )
        terminalManager.createSession(
            kind: .projectAction,
            title: context.title,
            threadID: context.threadID,
            threadName: context.threadName,
            currentDirectory: context.currentDirectory,
            maxSessions: ProjectActionTerminalPresentation.maxSessions(settings: settings),
            launchConfiguration: launchConfiguration
        )
        if ProjectActionTerminalPresentation.shouldAutoExpand(settings: settings) {
            appState.showTerminalPane()
        }
    }

    /// Re-resolves the owner the buttons were loaded for; a thread archived or a
    /// project removed since the load runs nothing.
    private func resolvedProjectActionExecutionContext(
        owner: ToolbarProjectActionsOwner,
        action: AlvearyProjectConfig.ProjectAction
    ) -> ProjectActionExecutionContext? {
        switch owner {
        case .folder(let owner, let folder):
            let thread: AgentThread?
            switch owner {
            case .thread(let id):
                guard let live = uiModelContext.resolveThread(id: id), live.archivedAt == nil,
                      live.workspaceFolderTargets.contains(folder) else { return nil }
                thread = live
            case .project(let id):
                guard let live = uiModelContext.resolveProject(projectID: id),
                      live.workspaceFolderTargets.contains(folder) else { return nil }
                thread = nil
            }
            do { _ = try folder.requireDirectory() } catch {
                appState.presentUnexpectedError(message: error.localizedDescription)
                return nil
            }
            return ProjectActionExecutionContext(folder: folder, thread: thread, action: action)
        }
    }

    func ensureDefaultShellSession(focus: Bool) {
        if !terminalManager.sessions.contains(where: { $0.kind == .shell }) {
            createTerminalShellSession(focus: focus)
            return
        }

        terminalManager.ensureSelection()
        if focus, let selectedSessionID = terminalManager.selectedSession?.id {
            terminalManager.requestFocus(id: selectedSessionID)
        }
    }

    func createTerminalShellSession(focus: Bool) {
        if case .thread = appState.selectedSidebarItem, selectedWorkspaceFolder == nil {
            appState.presentUnexpectedError(message: WorkspaceFolderError.invalidSnapshot.localizedDescription)
            return
        }
        var context = TerminalDefaultShellContextResolver.resolve(
            selection: appState.selectedSidebarItem,
            modelContext: uiModelContext
        )
        if let folder = selectedWorkspaceFolder {
            do { _ = try folder.requireDirectory() } catch {
                appState.presentUnexpectedError(message: error.localizedDescription)
                return
            }
            context.currentDirectory = folder.directory
        }
        let launchConfiguration = TerminalLaunchBuilder().shell(currentDirectory: context.currentDirectory)
        terminalManager.createSession(
            kind: .shell,
            title: context.title,
            threadID: context.threadID,
            threadName: context.threadName,
            currentDirectory: context.currentDirectory,
            select: true,
            focus: focus,
            maxSessions: ProjectActionTerminalPresentation.maxSessions(settings: settingsService.current),
            launchConfiguration: launchConfiguration
        )
    }
}
