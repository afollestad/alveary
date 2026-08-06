import Darwin
import Foundation

enum ExecutableSearchPath {
    static let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    static let defaultFallbackExecutableDirectories = [
        "~/.local/bin",
        "~/.claude/local",
        "/opt/homebrew/bin",
        "/usr/local/bin"
    ]

    static func augmentedPath(
        _ path: String?,
        fallbackDirectories: [String] = defaultFallbackExecutableDirectories
    ) -> String {
        var components = (path ?? defaultPath)
            .split(separator: ":")
            .map(String.init)

        for directory in fallbackDirectories {
            let expandedDirectory = expandHomeDirectory(in: directory)
            guard !expandedDirectory.isEmpty, !components.contains(expandedDirectory) else {
                continue
            }
            components.append(expandedDirectory)
        }

        return components.joined(separator: ":")
    }

    static func expandHomeDirectory(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        return NSHomeDirectory() + String(path.dropFirst())
    }
}

protocol ExecutablePathResolving: Sendable {
    func resolveExecutablePath(for candidate: String) async -> String?
}

actor DefaultExecutablePathResolver: ExecutablePathResolving {
    private let shell: ShellRunner
    private let fallbackExecutableDirectories: [String]
    private let fileManager: FileManager
    /// Successful resolutions only, for the life of the process — the app-scoped
    /// `AppComponent.executablePathResolver` is the only instance production uses.
    /// Probing costs a `/usr/bin/which` spawn and, on a miss, a login shell per
    /// candidate shell, which every `gh` call and every provider re-check paid.
    private var cachedPaths: [String: String] = [:]
    /// In-flight probes, so simultaneous callers share one spawn instead of racing.
    /// The actor suspends at its first `await`, so a plain cache alone would not
    /// dedupe a pane's detail and diff legs starting together.
    private var pendingResolutions: [String: Task<String?, Never>] = [:]

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
            // An explicit path needs no search, so it never reaches the cache.
            let path = expandHomeDirectory(in: candidate)
            return fileManager.isExecutableFile(atPath: path) ? path : nil
        }

        if let cached = cachedPaths[candidate] {
            // A stat, not a subprocess: catches an uninstall so a vanished binary
            // re-probes rather than failing at `Process.run`.
            if fileManager.isExecutableFile(atPath: cached) {
                return cached
            }
            cachedPaths[candidate] = nil
        }

        if let pending = pendingResolutions[candidate] {
            return await pending.value
        }

        // Unstructured on purpose: the probe outlives any one caller, so a cancelled
        // pane load cannot kill a spawn that other callers are sharing.
        let resolution = Task { await probeExecutablePath(for: candidate) }
        pendingResolutions[candidate] = resolution
        let resolved = await resolution.value
        pendingResolutions[candidate] = nil
        if let resolved {
            cachedPaths[candidate] = resolved
        }
        // Failures stay uncached: onboarding re-checks a dependency right after
        // installing it, and the post-wake sweep re-checks every provider, so a
        // cached negative would hide a binary that has since appeared.
        return resolved
    }

    private func probeExecutablePath(for candidate: String) async -> String? {
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
        ExecutableSearchPath.defaultFallbackExecutableDirectories
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
        ExecutableSearchPath.expandHomeDirectory(in: path)
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
