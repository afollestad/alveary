import Darwin
import Foundation

struct TerminalLaunchConfiguration: Equatable, Sendable {
    let executable: String
    let args: [String]
    let environment: [String]
    let execName: String
    let currentDirectory: String
}

struct TerminalLaunchBuilder: Sendable {
    var environment: @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    var homeDirectory: @Sendable () -> String = { NSHomeDirectory() }
    var userName: @Sendable () -> String = { NSUserName() }
    var passwdShell: @Sendable () -> String? = {
        guard let passwd = getpwuid(getuid()),
              let shell = passwd.pointee.pw_shell else {
            return nil
        }

        return String(cString: shell)
    }
    var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }

    func shell(currentDirectory: String) -> TerminalLaunchConfiguration {
        let shellPath = resolvedShellPath()
        return configuration(
            shellPath: shellPath,
            args: [],
            currentDirectory: currentDirectory
        )
    }

    func projectAction(command: String, currentDirectory: String) -> TerminalLaunchConfiguration {
        let shellPath = resolvedShellPath()
        return configuration(
            shellPath: shellPath,
            args: ["-i", "-c", command],
            currentDirectory: currentDirectory
        )
    }

    func defaultShellDirectory(
        threadWorktreePath: String?,
        threadProjectPath: String?,
        selectedProjectPath: String?
    ) -> String {
        firstNonEmptyPath([
            threadWorktreePath,
            threadProjectPath,
            selectedProjectPath,
            homeDirectory()
        ])
    }

    func resolvedShellPath() -> String {
        let shellCandidates = [
            environment()["SHELL"],
            passwdShell()
        ].compactMap(normalizedPath)

        if let zshCandidate = shellCandidates.first(where: { candidate in
            URL(fileURLWithPath: candidate).lastPathComponent == "zsh" && isExecutable(candidate)
        }) {
            return zshCandidate
        }

        if isExecutable("/bin/zsh") {
            return "/bin/zsh"
        }

        if let executableCandidate = shellCandidates.first(where: isExecutable) {
            return executableCandidate
        }

        return "/bin/bash"
    }

    private func configuration(
        shellPath: String,
        args: [String],
        currentDirectory: String
    ) -> TerminalLaunchConfiguration {
        TerminalLaunchConfiguration(
            executable: shellPath,
            args: args,
            environment: serializedEnvironment(shellPath: shellPath, currentDirectory: currentDirectory),
            execName: "-" + URL(fileURLWithPath: shellPath).lastPathComponent,
            currentDirectory: currentDirectory
        )
    }

    private func serializedEnvironment(shellPath: String, currentDirectory: String) -> [String] {
        var values = environment()
        values["HOME"] = homeDirectory()
        values["USER"] = userName()
        values["SHELL"] = shellPath
        values["PWD"] = currentDirectory
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        values["TERM_PROGRAM"] = "Alveary"
        values["LANG"] = values["LANG"] ?? "en_US.UTF-8"
        values["LC_CTYPE"] = values["LC_CTYPE"] ?? "en_US.UTF-8"
        values["PATH"] = ExecutableSearchPath.augmentedPath(values["PATH"])

        return values
            .map { key, value in "\(key)=\(value)" }
            .sorted()
    }

    private func firstNonEmptyPath(_ paths: [String?]) -> String {
        for path in paths {
            if let normalizedPath = normalizedPath(path) {
                return normalizedPath
            }
        }

        return homeDirectory()
    }

    private func normalizedPath(_ path: String?) -> String? {
        guard let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedPath.isEmpty else {
            return nil
        }

        return trimmedPath
    }
}
