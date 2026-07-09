import SwiftData
import SwiftUI

struct ProjectActionExecutionContext: Equatable {
    let title: String
    let threadID: PersistentIdentifier
    let threadName: String
    let currentDirectory: String
    let command: String

    init?(thread: AgentThread, action: AlvearyProjectConfig.ProjectAction) {
        guard let currentDirectory = thread.worktreePath ?? thread.project?.path else {
            return nil
        }

        self.title = action.name
        self.threadID = thread.persistentModelID
        self.threadName = thread.name
        self.currentDirectory = currentDirectory
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

extension ContentView {
    func runProjectAction(threadID: PersistentIdentifier, action: AlvearyProjectConfig.ProjectAction) {
        guard let thread = uiModelContext.resolveThread(id: threadID),
              thread.archivedAt == nil else {
            return
        }
        guard let context = ProjectActionExecutionContext(thread: thread, action: action) else {
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
        let context = defaultTerminalShellContext()
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

    private func defaultTerminalShellContext() -> TerminalDefaultShellContext {
        let builder = TerminalLaunchBuilder()

        switch appState.selectedSidebarItem {
        case .thread(let selectedThread):
            guard let thread = uiModelContext.resolveThread(id: selectedThread.persistentModelID),
                  thread.archivedAt == nil else {
                return TerminalDefaultShellContext(
                    currentDirectory: builder.defaultShellDirectory(
                        threadWorktreePath: nil,
                        threadProjectPath: nil,
                        selectedProjectPath: nil
                    )
                )
            }

            return TerminalDefaultShellContext(
                threadID: thread.persistentModelID,
                threadName: thread.name,
                currentDirectory: builder.defaultShellDirectory(
                    threadWorktreePath: thread.worktreePath,
                    threadProjectPath: thread.project?.path,
                    selectedProjectPath: nil
                )
            )
        case .project(let project):
            return TerminalDefaultShellContext(
                currentDirectory: builder.defaultShellDirectory(
                    threadWorktreePath: nil,
                    threadProjectPath: nil,
                    selectedProjectPath: project.path
                )
            )
        case .skills, .mcp, .settings, nil:
            return TerminalDefaultShellContext(
                currentDirectory: builder.defaultShellDirectory(
                    threadWorktreePath: nil,
                    threadProjectPath: nil,
                    selectedProjectPath: nil
                )
            )
        }
    }
}

private struct TerminalDefaultShellContext {
    var title = "Shell"
    var threadID: PersistentIdentifier?
    var threadName: String?
    var currentDirectory: String
}
