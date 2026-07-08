import Foundation

enum OnboardingDependency: String, CaseIterable, Identifiable, Sendable, Equatable {
    case githubCLI
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .githubCLI:
            return "GitHub CLI"
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    var required: Bool {
        self == .githubCLI
    }

    var providerID: String? {
        switch self {
        case .githubCLI:
            return nil
        case .claude:
            return "claude"
        case .codex:
            return "codex"
        }
    }

    var fallbackInstallCommand: String {
        switch self {
        case .githubCLI:
            return "brew install gh"
        case .claude:
            return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex:
            return "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        }
    }
}

struct OnboardingDependencyStatus: Sendable, Equatable {
    let dependency: OnboardingDependency
    let state: State

    enum State: Sendable, Equatable {
        case installed(detail: String?)
        case missing
    }

    var isInstalled: Bool {
        if case .installed = state {
            return true
        }
        return false
    }
}

struct OnboardingDependencyInstallError: LocalizedError, Sendable, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
protocol OnboardingDependencyService: AnyObject {
    func status(for dependency: OnboardingDependency) async -> OnboardingDependencyStatus
    func install(_ dependency: OnboardingDependency) async throws -> OnboardingDependencyStatus
}

@MainActor
final class DefaultOnboardingDependencyService: OnboardingDependencyService {
    private static let installerTimeout: Duration = .seconds(1_800)
    private static let outputLimitBytes = 128 * 1024
    private static let homebrewInstallCommand = "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    private let gitHubCLI: GitHubCLIService
    private let providerDetection: any ProviderDetectionService
    private let agentRegistry: AgentRegistry
    private let shell: ShellRunner
    private let executableResolver: any ExecutablePathResolving

    init(
        gitHubCLI: GitHubCLIService,
        providerDetection: any ProviderDetectionService,
        agentRegistry: AgentRegistry,
        shell: ShellRunner,
        executableResolver: any ExecutablePathResolving
    ) {
        self.gitHubCLI = gitHubCLI
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.shell = shell
        self.executableResolver = executableResolver
    }

    func status(for dependency: OnboardingDependency) async -> OnboardingDependencyStatus {
        switch dependency {
        case .githubCLI:
            if let version = await gitHubCLI.checkInstalled(), !version.isEmpty {
                return OnboardingDependencyStatus(dependency: dependency, state: .installed(detail: version))
            }
            return OnboardingDependencyStatus(dependency: dependency, state: .missing)
        case .claude, .codex:
            guard let providerID = dependency.providerID else {
                return OnboardingDependencyStatus(dependency: dependency, state: .missing)
            }
            await providerDetection.checkProvider(providerID)
            guard let path = await providerDetection.resolvedPath(for: providerID) else {
                return OnboardingDependencyStatus(dependency: dependency, state: .missing)
            }
            let detail: String?
            switch await providerDetection.status(for: providerID) {
            case .connected(path: _, version: let version):
                let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
                detail = trimmedVersion.isEmpty ? path : "\(trimmedVersion) at \(path)"
            default:
                detail = path
            }
            return OnboardingDependencyStatus(dependency: dependency, state: .installed(detail: detail))
        }
    }

    func install(_ dependency: OnboardingDependency) async throws -> OnboardingDependencyStatus {
        let currentStatus = await status(for: dependency)
        if currentStatus.isInstalled {
            return currentStatus
        }

        switch dependency {
        case .githubCLI:
            return try await installGitHubCLI()
        case .claude, .codex:
            return try await installAgentDependency(dependency)
        }
    }

    private func installGitHubCLI() async throws -> OnboardingDependencyStatus {
        var lastResult: ShellResult?
        var brewPath = await executableResolver.resolveExecutablePath(for: "brew")
        if brewPath == nil {
            lastResult = try await runInstaller(
                executable: "/bin/bash",
                args: ["-c", Self.homebrewInstallCommand]
            )
            brewPath = await executableResolver.resolveExecutablePath(for: "brew")
            guard brewPath != nil else {
                throw postconditionFailure(
                    "Homebrew installer finished, but `brew` could not be found.",
                    result: lastResult
                )
            }
        }

        guard let brewPath else {
            throw OnboardingDependencyInstallError(message: "Unable to locate `brew`.")
        }

        lastResult = try await runInstaller(
            executable: brewPath,
            args: ["install", "gh"],
            environment: ["NONINTERACTIVE": "1"]
        )
        let installedStatus = await status(for: .githubCLI)
        guard installedStatus.isInstalled else {
            throw postconditionFailure(
                "`brew install gh` finished, but `gh` could not be found.",
                result: lastResult
            )
        }
        return installedStatus
    }

    private func installAgentDependency(_ dependency: OnboardingDependency) async throws -> OnboardingDependencyStatus {
        guard let providerID = dependency.providerID else {
            throw OnboardingDependencyInstallError(message: "Unsupported dependency: \(dependency.displayName)")
        }
        let command = agentRegistry.agent(for: providerID)?.installCommand ?? dependency.fallbackInstallCommand
        let environment = dependency == .codex ? ["CODEX_NON_INTERACTIVE": "1"] : nil
        let result = try await runInstaller(
            executable: "/bin/bash",
            args: ["-lc", command],
            environment: environment
        )

        let installedStatus = await status(for: dependency)
        guard installedStatus.isInstalled else {
            throw postconditionFailure(
                "\(dependency.displayName) installer finished, but `\(providerID)` could not be found.",
                result: result
            )
        }
        return installedStatus
    }

    private func runInstaller(
        executable: String,
        args: [String],
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        do {
            let result = try await shell.run(
                executable: executable,
                args: args,
                environment: environment,
                timeout: Self.installerTimeout,
                stdoutLimitBytes: Self.outputLimitBytes,
                stderrLimitBytes: Self.outputLimitBytes,
                standardInput: .nullDevice
            )
            guard result.succeeded else {
                throw installFailure(command: executable, result: result)
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OnboardingDependencyInstallError {
            throw error
        } catch let error as ShellError {
            throw OnboardingDependencyInstallError(message: error.localizedDescription)
        } catch {
            throw OnboardingDependencyInstallError(message: error.localizedDescription)
        }
    }

    private func installFailure(command: String, result: ShellResult) -> OnboardingDependencyInstallError {
        let message = outputMessage(
            prefix: "`\(command)` failed with exit code \(result.exitCode).",
            result: result
        )
        return OnboardingDependencyInstallError(message: message)
    }

    private func postconditionFailure(_ prefix: String, result: ShellResult?) -> OnboardingDependencyInstallError {
        guard let result else {
            return OnboardingDependencyInstallError(message: prefix)
        }
        return OnboardingDependencyInstallError(message: outputMessage(prefix: prefix, result: result))
    }

    private func outputMessage(prefix: String, result: ShellResult) -> String {
        var parts = [prefix]
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            parts.append(stderr)
        } else if !stdout.isEmpty {
            parts.append(stdout)
        }
        if result.stderrWasTruncated || result.stdoutWasTruncated {
            parts.append("Output was truncated.")
        }
        return parts.joined(separator: " ")
    }
}
