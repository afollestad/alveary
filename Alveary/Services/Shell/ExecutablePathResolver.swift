import Darwin
import Foundation

protocol ExecutablePathResolving: Sendable {
    func resolveExecutablePath(for candidate: String) async -> String?
}

actor DefaultExecutablePathResolver: ExecutablePathResolving {
    private let shell: ShellRunner
    private let fallbackExecutableDirectories: [String]
    private let fileManager: FileManager

    init(
        shell: ShellRunner,
        fallbackExecutableDirectories: [String] = DefaultExecutablePathResolver.defaultFallbackExecutableDirectories,
        fileManager: FileManager = .default
    ) {
        self.shell = shell
        self.fallbackExecutableDirectories = fallbackExecutableDirectories
        self.fileManager = fileManager
    }

    func resolveExecutablePath(for candidate: String) async -> String? {
        if candidate.contains("/") {
            let path = expandHomeDirectory(in: candidate)
            return fileManager.isExecutableFile(atPath: path) ? path : nil
        }

        let whichResult = try? await shell.run(
            executable: "/usr/bin/which",
            args: [candidate],
            timeout: .seconds(2)
        )

        if let whichResult,
           whichResult.succeeded {
            let resolvedPath = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedPath.isEmpty {
                return resolvedPath
            }
        }

        if let loginShellPath = await resolveExecutablePathWithLoginShell(candidate) {
            return loginShellPath
        }

        for directory in fallbackExecutableDirectories {
            let resolvedPath = URL(fileURLWithPath: expandHomeDirectory(in: directory))
                .appendingPathComponent(candidate)
                .path
            if fileManager.isExecutableFile(atPath: resolvedPath) {
                return resolvedPath
            }
        }

        return nil
    }
}

extension DefaultExecutablePathResolver {
    static var defaultFallbackExecutableDirectories: [String] {
        [
            "~/.local/bin",
            "~/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
    }
}

private extension DefaultExecutablePathResolver {
    func resolveExecutablePathWithLoginShell(_ candidate: String) async -> String? {
        let outputPrefix = "__ALVEARY_EXECUTABLE_PATH__"
        let command = "resolved=$(command -v \(shellQuoted(candidate))) && printf '%s%s\\n' '\(outputPrefix)' \"$resolved\""
        for shellPath in Self.loginShellExecutablePaths where fileManager.isExecutableFile(atPath: shellPath) {
            let result = try? await shell.run(
                executable: shellPath,
                args: ["-lc", command],
                timeout: .seconds(2)
            )
            guard let result,
                  result.succeeded,
                  let resolvedPath = result.stdout
                  .split(whereSeparator: \.isNewline)
                  .first(where: { $0.hasPrefix(outputPrefix) })?
                  .dropFirst(outputPrefix.count)
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  fileManager.isExecutableFile(atPath: resolvedPath) else {
                continue
            }
            return resolvedPath
        }
        return nil
    }

    func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func expandHomeDirectory(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        return NSHomeDirectory() + String(path.dropFirst())
    }

    static var loginShellExecutablePaths: [String] {
        var paths: [String] = []
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           !shell.isEmpty {
            paths.append(shell)
        }
        if let passwd = getpwuid(getuid()),
           let shell = passwd.pointee.pw_shell {
            paths.append(String(cString: shell))
        }
        paths.append(contentsOf: ["/bin/zsh", "/bin/bash"])
        return paths.reduce(into: []) { uniquePaths, path in
            if !uniquePaths.contains(path) {
                uniquePaths.append(path)
            }
        }
    }
}
