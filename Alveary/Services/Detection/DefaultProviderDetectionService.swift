import Darwin
import Foundation

actor DefaultProviderDetectionService: ProviderDetectionService {
    private let shell: ShellRunner
    private let registry: ProviderRegistry
    private let fallbackExecutableDirectories: [String]
    private var statuses: [String: ProviderStatus] = [:]
    private var resolvedPaths: [String: String] = [:]

    init(
        shell: ShellRunner,
        registry: ProviderRegistry,
        fallbackExecutableDirectories: [String] = DefaultProviderDetectionService.defaultFallbackExecutableDirectories
    ) {
        self.shell = shell
        self.registry = registry
        self.fallbackExecutableDirectories = fallbackExecutableDirectories
    }

    func resolvedPath(for providerId: String) -> String? {
        resolvedPaths[providerId]
    }

    func status(for providerId: String) -> ProviderStatus {
        statuses[providerId] ?? .unchecked
    }

    func checkAllProviders() async {
        for provider in registry.providers {
            await checkProvider(provider.id)
        }
    }

    func checkProvider(_ providerId: String) async {
        guard let provider = registry.provider(for: providerId) else {
            return
        }
        await checkProvider(provider, timeoutSeconds: 3, attempt: 1)
    }

    private func checkProvider(_ provider: ProviderDefinition, timeoutSeconds: Int, attempt: Int) async {
        for candidate in provider.commands {
            guard let path = await resolveExecutablePath(for: candidate) else {
                continue
            }

            do {
                let result = try await shell.run(
                    executable: path,
                    args: provider.versionArgs,
                    timeout: .seconds(timeoutSeconds)
                )

                if result.succeeded {
                    let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    statuses[provider.id] = .connected(path: path, version: version)
                    resolvedPaths[provider.id] = path
                    return
                }

                statuses[provider.id] = classifyFailure(stdout: result.stdout, stderr: result.stderr)
                resolvedPaths[provider.id] = path
                return
            } catch let error as ShellError {
                switch error {
                case .timeout:
                    if attempt < 3 {
                        try? await Task.sleep(for: .seconds(1.5))
                        await checkProvider(provider, timeoutSeconds: min(timeoutSeconds * 2, 12), attempt: attempt + 1)
                        return
                    }
                    statuses[provider.id] = .error("Version check timed out after \(attempt) attempts")
                    resolvedPaths[provider.id] = path
                    return
                }
            } catch {
                statuses[provider.id] = .error(error.localizedDescription)
                resolvedPaths[provider.id] = path
                return
            }
        }

        statuses[provider.id] = .missing
        resolvedPaths.removeValue(forKey: provider.id)
    }

    private func resolveExecutablePath(for candidate: String) async -> String? {
        if candidate.contains("/") {
            let path = expandHomeDirectory(in: candidate)
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
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
            if FileManager.default.isExecutableFile(atPath: resolvedPath) {
                return resolvedPath
            }
        }

        return nil
    }

    private func resolveExecutablePathWithLoginShell(_ candidate: String) async -> String? {
        let outputPrefix = "__ALVEARY_EXECUTABLE_PATH__"
        let command = "resolved=$(command -v \(shellQuoted(candidate))) && printf '%s%s\\n' '\(outputPrefix)' \"$resolved\""
        for shellPath in Self.loginShellExecutablePaths where FileManager.default.isExecutableFile(atPath: shellPath) {
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
                  FileManager.default.isExecutableFile(atPath: resolvedPath) else {
                continue
            }
            return resolvedPath
        }
        return nil
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func expandHomeDirectory(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        return NSHomeDirectory() + String(path.dropFirst())
    }

    private func classifyFailure(stdout: String, stderr: String) -> ProviderStatus {
        let combinedOutput = "\(stdout)\n\(stderr)".lowercased()
        if combinedOutput.contains("api key") ||
            combinedOutput.contains("not authenticated") ||
            combinedOutput.contains("auth login") {
            return .needsKey
        }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .error(message.isEmpty ? "Provider check failed" : message)
    }

    private static var defaultFallbackExecutableDirectories: [String] {
        [
            "~/.local/bin",
            "~/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
    }

    private static var loginShellExecutablePaths: [String] {
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
