import SwiftData
import SwiftUI

struct ProjectActionExecutionContext: Equatable {
    let title: String
    let projectName: String?
    let threadID: PersistentIdentifier
    let threadName: String
    let currentDirectory: String
    let command: String

    init?(thread: AgentThread, action: AlvearyProjectConfig.ProjectAction) {
        guard let currentDirectory = thread.worktreePath ?? thread.project?.path else {
            return nil
        }

        self.title = action.name
        self.projectName = thread.project?.name
        self.threadID = thread.persistentModelID
        self.threadName = thread.name
        self.currentDirectory = currentDirectory
        self.command = action.command
    }
}

enum ProjectActionOutputFormatter {
    static func format(_ result: ShellResult) -> String {
        var sections: [String] = []

        if !result.stdout.isEmpty {
            sections.append(result.stdout)
        }

        if !result.stderr.isEmpty {
            sections.append(result.stdout.isEmpty ? result.stderr : "stderr:\n\(result.stderr)")
        }

        if result.stdoutWasTruncated {
            sections.append("stdout was truncated.")
        }

        if result.stderrWasTruncated {
            sections.append("stderr was truncated.")
        }

        return sections.joined(separator: "\n\n")
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

        let sessionID = terminalManager.createSession(
            title: context.title,
            projectName: context.projectName,
            threadID: context.threadID,
            threadName: context.threadName,
            currentDirectory: context.currentDirectory,
            command: context.command,
            maxSessions: ProjectActionTerminalPresentation.maxSessions(settings: settingsService.current)
        )
        if ProjectActionTerminalPresentation.shouldAutoExpand(settings: settingsService.current) {
            appState.showTerminalPane()
        }

        let task = Task {
            do {
                let result = try await shellRunner.run(
                    executable: "/bin/sh",
                    args: ["-c", context.command],
                    in: context.currentDirectory
                )
                let output = ProjectActionOutputFormatter.format(result)

                if !output.isEmpty {
                    terminalManager.appendOutput(output, to: sessionID)
                }
                terminalManager.markSessionFinished(id: sessionID, exitCode: result.exitCode)
            } catch is CancellationError {
                terminalManager.cancelSession(id: sessionID)
            } catch {
                terminalManager.appendOutput(error.localizedDescription, to: sessionID)
                terminalManager.markSessionFinished(id: sessionID, exitCode: 1)
            }
        }

        terminalManager.registerTask(task, forSessionID: sessionID)
    }
}
