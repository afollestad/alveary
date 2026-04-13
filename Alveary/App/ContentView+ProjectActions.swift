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

extension ContentView {
    func runProjectAction(thread: AgentThread, action: AlvearyProjectConfig.ProjectAction) {
        guard let context = ProjectActionExecutionContext(thread: thread, action: action) else {
            return
        }

        let sessionID = terminalManager.createSession(
            title: context.title,
            projectName: context.projectName,
            threadID: context.threadID,
            threadName: context.threadName,
            currentDirectory: context.currentDirectory,
            command: context.command
        )
        appState.showTerminalPane()

        Task {
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
            } catch {
                terminalManager.appendOutput(error.localizedDescription, to: sessionID)
                terminalManager.markSessionFinished(id: sessionID, exitCode: 1)
            }
        }
    }
}
