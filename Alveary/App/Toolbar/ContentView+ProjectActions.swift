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

    init?(thread: AgentThread, action: AlvearyProjectConfig.ProjectAction) {
        guard thread.effectiveMode == .project,
              let currentDirectory = thread.primaryWorkingDirectory else {
            return nil
        }

        self.title = action.name
        self.threadID = thread.persistentModelID
        self.threadName = thread.name
        self.currentDirectory = currentDirectory
        self.command = action.command
    }

    init(projectPath: String, action: AlvearyProjectConfig.ProjectAction) {
        self.title = action.name
        self.threadID = nil
        self.threadName = nil
        self.currentDirectory = projectPath
        self.command = action.command
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
                let draftDirectory = thread.effectiveMode == .task
                    ? thread.primaryWorkingDirectory
                    : thread.project?.path
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
            let projectPath = modelContext.resolveProject(id: selectedProject.persistentModelID)?.path
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
        case .thread(let threadID):
            guard let thread = uiModelContext.resolveThread(id: threadID),
                  thread.archivedAt == nil else {
                return nil
            }
            return ProjectActionExecutionContext(thread: thread, action: action)
        case .project(let path):
            guard let project = uiModelContext.resolveProject(path: path) else {
                return nil
            }
            return ProjectActionExecutionContext(projectPath: project.path, action: action)
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
        let context = TerminalDefaultShellContextResolver.resolve(
            selection: appState.selectedSidebarItem,
            modelContext: uiModelContext
        )
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
