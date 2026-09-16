import AgentCLIKit
import Foundation

actor DefaultHarnessDetectionService: HarnessDetectionService {
    private let shell: ShellRunner
    private let registry: HarnessRegistry
    private let executableResolver: any ExecutablePathResolving
    private var statuses: [String: HarnessStatus] = [:]
    private var resolvedPaths: [String: String] = [:]

    init(
        shell: ShellRunner,
        registry: HarnessRegistry,
        fallbackExecutableDirectories: [String] = DefaultExecutablePathResolver.defaultFallbackExecutableDirectories
    ) {
        self.shell = shell
        self.registry = registry
        self.executableResolver = DefaultExecutablePathResolver(
            shell: shell,
            fallbackExecutableDirectories: fallbackExecutableDirectories
        )
    }

    init(
        shell: ShellRunner,
        registry: HarnessRegistry,
        executableResolver: any ExecutablePathResolving
    ) {
        self.shell = shell
        self.registry = registry
        self.executableResolver = executableResolver
    }

    func resolvedPath(for harnessId: String) -> String? {
        resolvedPaths[harnessId]
    }

    func status(for harnessId: String) -> HarnessStatus {
        statuses[harnessId] ?? .unchecked
    }

    func checkAllHarnesses() async {
        await withTaskGroup(of: Void.self) { group in
            for harness in registry.harnesses {
                group.addTask { await self.checkHarness(harness.id) }
            }
        }
    }

    func checkHarness(_ harnessId: String) async {
        guard let harness = registry.harness(for: harnessId) else {
            return
        }
        await checkHarness(harness, timeoutSeconds: 3, attempt: 1)
    }

    private func checkHarness(_ harness: HarnessDefinition, timeoutSeconds: Int, attempt: Int) async {
        for candidate in harness.commands {
            guard let path = await executableResolver.resolveExecutablePath(for: candidate) else {
                continue
            }

            do {
                let result = try await shell.run(
                    executable: path,
                    args: harness.versionArgs,
                    timeout: .seconds(timeoutSeconds)
                )

                if result.succeeded {
                    let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if harness.id == "opencode" {
                        try OpenCodeVersionSupport.validate(version)
                    }
                    statuses[harness.id] = .connected(path: path, version: version)
                    resolvedPaths[harness.id] = path
                    return
                }

                statuses[harness.id] = classifyFailure(stdout: result.stdout, stderr: result.stderr)
                resolvedPaths[harness.id] = path
                return
            } catch let error as ShellError {
                switch error {
                case .invalidDirectory, .launchFailed:
                    statuses[harness.id] = .error(error.localizedDescription)
                    resolvedPaths[harness.id] = path
                    return
                case .timeout:
                    if attempt < 3 {
                        try? await Task.sleep(for: .seconds(1.5))
                        await checkHarness(harness, timeoutSeconds: min(timeoutSeconds * 2, 12), attempt: attempt + 1)
                        return
                    }
                    statuses[harness.id] = .error("Version check timed out after \(attempt) attempts")
                    resolvedPaths[harness.id] = path
                    return
                case .ioFailure:
                    statuses[harness.id] = .error(error.localizedDescription)
                    resolvedPaths[harness.id] = path
                    return
                }
            } catch {
                statuses[harness.id] = .error(error.localizedDescription)
                resolvedPaths[harness.id] = path
                return
            }
        }

        statuses[harness.id] = .missing
        resolvedPaths.removeValue(forKey: harness.id)
    }

    private func classifyFailure(stdout: String, stderr: String) -> HarnessStatus {
        let combinedOutput = "\(stdout)\n\(stderr)".lowercased()
        if combinedOutput.contains("api key") ||
            combinedOutput.contains("not authenticated") ||
            combinedOutput.contains("auth login") {
            return .needsKey
        }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .error(message.isEmpty ? "Harness check failed" : message)
    }
}
