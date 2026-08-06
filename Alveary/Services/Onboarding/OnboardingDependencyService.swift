import Foundation

enum OnboardingDependency: String, CaseIterable, Identifiable, Sendable, Equatable {
    // Declaration order drives both row order and refresh order.
    case commandLineTools
    case githubCLI
    case claude
    case codex

    static var requiredCases: [OnboardingDependency] {
        allCases.filter(\.required)
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandLineTools:
            return "Command Line Tools"
        case .githubCLI:
            return "GitHub CLI"
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    var required: Bool {
        switch self {
        case .commandLineTools, .githubCLI:
            return true
        case .claude, .codex:
            return false
        }
    }

    var providerID: String? {
        switch self {
        case .commandLineTools, .githubCLI:
            return nil
        case .claude:
            return "claude"
        case .codex:
            return "codex"
        }
    }

    var fallbackInstallCommand: String {
        switch self {
        case .commandLineTools:
            return "xcode-select --install"
        case .githubCLI:
            return "brew install gh"
        case .claude:
            return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex:
            return "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        }
    }

    /// Shown on a failed required row so a broken installer is never a dead end.
    var manualInstallGuidance: (command: String, helpURL: URL?)? {
        switch self {
        case .commandLineTools:
            return (fallbackInstallCommand, nil)
        case .githubCLI:
            // `brew install gh` only helps if Homebrew exists, so always offer the download page too.
            return (fallbackInstallCommand, URL(string: "https://cli.github.com"))
        case .claude, .codex:
            return nil
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

    private let gitHubCLI: GitHubCLIService
    private let providerDetection: any ProviderDetectionService
    private let agentRegistry: AgentRegistry
    // Internal so the Command Line Tools companion can probe with it.
    let shell: ShellRunner
    let commandLineToolsPollInterval: Duration
    private let executableResolver: any ExecutablePathResolving
    private let standaloneGitHubCLIInstaller: any StandaloneGitHubCLIInstalling

    init(
        gitHubCLI: GitHubCLIService,
        providerDetection: any ProviderDetectionService,
        agentRegistry: AgentRegistry,
        shell: ShellRunner,
        executableResolver: any ExecutablePathResolving,
        standaloneGitHubCLIInstaller: (any StandaloneGitHubCLIInstalling)? = nil,
        commandLineToolsPollInterval: Duration = .seconds(5)
    ) {
        self.gitHubCLI = gitHubCLI
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.shell = shell
        self.commandLineToolsPollInterval = commandLineToolsPollInterval
        self.executableResolver = executableResolver
        self.standaloneGitHubCLIInstaller = standaloneGitHubCLIInstaller
            ?? StandaloneGitHubCLIInstaller(shell: shell)
    }

    func status(for dependency: OnboardingDependency) async -> OnboardingDependencyStatus {
        switch dependency {
        case .commandLineTools:
            return await commandLineToolsStatus()
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
        case .commandLineTools:
            return try await installCommandLineTools()
        case .githubCLI:
            return try await installGitHubCLI()
        case .claude, .codex:
            return try await installAgentDependency(dependency)
        }
    }

    private func installGitHubCLI() async throws -> OnboardingDependencyStatus {
        // Never bootstrap Homebrew here. Its installer requires `sudo`, and these installers run
        // with null stdin by design, so the prompt can only abort after a long silent wait.
        guard let brewPath = await executableResolver.resolveExecutablePath(for: "brew") else {
            try await standaloneGitHubCLIInstaller.install()
            let installedStatus = await status(for: .githubCLI)
            guard installedStatus.isInstalled else {
                throw OnboardingDependencyInstallError(
                    message: """
                    The GitHub CLI was downloaded, but `gh` could not be found afterwards. \
                    \(StandaloneGitHubCLIInstaller.manualInstallGuidance)
                    """
                )
            }
            return installedStatus
        }

        let result = try await runInstaller(
            executable: brewPath,
            args: ["install", "gh"],
            environment: ["NONINTERACTIVE": "1"]
        )
        let installedStatus = await status(for: .githubCLI)
        guard installedStatus.isInstalled else {
            throw postconditionFailure(
                "`brew install gh` finished, but `gh` could not be found.",
                result: result
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
        // These commands pipe `curl` into a shell. Without `pipefail` a failed download still exits
        // 0, so an offline install would report success and then fail detection for no clear reason.
        let result = try await runInstaller(
            executable: "/bin/bash",
            args: ["-lc", "set -o pipefail; \(command)"],
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
