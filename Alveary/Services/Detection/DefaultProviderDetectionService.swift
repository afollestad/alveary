import Foundation

actor DefaultProviderDetectionService: ProviderDetectionService {
    private let shell: ShellRunner
    private let registry: ProviderRegistry
    private let executableResolver: any ExecutablePathResolving
    private var statuses: [String: ProviderStatus] = [:]
    private var resolvedPaths: [String: String] = [:]

    init(
        shell: ShellRunner,
        registry: ProviderRegistry,
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
        registry: ProviderRegistry,
        executableResolver: any ExecutablePathResolving
    ) {
        self.shell = shell
        self.registry = registry
        self.executableResolver = executableResolver
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
            guard let path = await executableResolver.resolveExecutablePath(for: candidate) else {
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
}
