import AgentCLIKit
import Foundation

protocol AgentOneShotPromptService: Sendable {
    func generate(prompt: String, workingDirectory: String) async throws -> String
}

enum AgentOneShotPromptError: LocalizedError, Equatable {
    case untrustedProject(providerId: String, workingDirectory: String)
    case approvalRequested
    case promptRequired
    case emptyOutput
    case failed(String)
    case cancelled
    case timedOut

    var errorDescription: String? {
        switch self {
        case .untrustedProject(let providerId, let workingDirectory):
            return "Project is not trusted for \(providerId): \(workingDirectory)"
        case .approvalRequested:
            return "Commit message generation requested user approval."
        case .promptRequired:
            return "Commit message generation requested user input."
        case .emptyOutput:
            return "Commit message generation returned no message."
        case .failed(let message):
            return message
        case .cancelled:
            return "Commit message generation was cancelled."
        case .timedOut:
            return "Commit message generation timed out."
        }
    }
}

final class DefaultAgentOneShotPromptService: AgentOneShotPromptService, @unchecked Sendable {
    private static let readOnlyProjectGuidance = """
    Use only read-only file inspection. If project guidance is relevant, inspect nearby `AGENTS.md` or `CLAUDE.md` files.
    Do not run shell commands, edit files, request approvals, or wait for user input.
    """

    private let promptRunner: any AgentCLIKit.AgentOneShotPromptRunning
    private let settingsService: SettingsService
    private let providerSetup: ProviderSetupService
    private let providerDetection: ProviderDetectionService
    private let environmentBuilder: AgentEnvironmentBuilder
    private let timeout: Duration

    init(
        promptRunner: any AgentCLIKit.AgentOneShotPromptRunning,
        settingsService: SettingsService,
        providerSetup: ProviderSetupService,
        providerDetection: ProviderDetectionService,
        environmentBuilder: AgentEnvironmentBuilder,
        timeout: Duration = .seconds(120)
    ) {
        self.promptRunner = promptRunner
        self.settingsService = settingsService
        self.providerSetup = providerSetup
        self.providerDetection = providerDetection
        self.environmentBuilder = environmentBuilder
        self.timeout = timeout
    }

    func generate(prompt: String, workingDirectory: String) async throws -> String {
        do {
            let request = try await makeRequest(prompt: prompt, workingDirectory: workingDirectory)
            let result = try await promptRunner.generate(request)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw AgentOneShotPromptError.emptyOutput
            }
            return text
        } catch let error as AgentOneShotPromptError {
            throw error
        } catch let error as AgentCLIKit.AgentOneShotPromptError {
            throw Self.mappedError(error)
        } catch is CancellationError {
            throw AgentOneShotPromptError.cancelled
        } catch {
            if Task.isCancelled {
                throw AgentOneShotPromptError.cancelled
            }
            if let mappedError = Self.mappedDiagnosticError(error.localizedDescription) {
                throw mappedError
            }
            throw AgentOneShotPromptError.failed(error.localizedDescription)
        }
    }

    private func makeRequest(prompt: String, workingDirectory: String) async throws -> AgentCLIKit.AgentOneShotPromptRequest {
        try Task.checkCancellation()

        let settings = await settingsService.current.normalized()
        let providerId = settings.defaultProvider
        let normalizedWorkingDirectory = CanonicalPath.normalize(workingDirectory)

        try await prepareTrustedProject(
            providerId: providerId,
            workingDirectory: normalizedWorkingDirectory,
            autoTrust: settings.autoTrustProjects
        )

        let detectedPath = try await detectedExecutablePath(for: providerId)
        let configuredArguments = try parseExtraArgs(settings.providerConfigs[providerId]?.extraArgs ?? "")
        let arguments = ClaudeNativeSchedulingLaunchPolicy.arguments(
            providerID: providerId,
            configuredArguments: configuredArguments
        )
        let environment = ClaudeNativeSchedulingLaunchPolicy.environment(
            providerID: providerId,
            baseEnvironment: oneShotEnvironment(detectedPath: detectedPath)
        )

        return AgentCLIKit.AgentOneShotPromptRequest(
            providerId: try Self.agentProviderID(providerId),
            workingDirectory: URL(fileURLWithPath: normalizedWorkingDirectory, isDirectory: true),
            prompt: Self.promptWithReadOnlyProjectGuidance(prompt),
            arguments: arguments,
            environment: environment,
            model: Self.normalizedModel(settings.defaultModel),
            effort: settings.effort,
            timeout: Self.timeInterval(from: timeout),
            toolPolicy: .readOnly
        )
    }

    private func prepareTrustedProject(
        providerId: String,
        workingDirectory: String,
        autoTrust: Bool
    ) async throws {
        await providerSetup.prepareForSpawn(
            providerId: providerId,
            workingDirectory: workingDirectory,
            autoTrust: autoTrust
        )
        guard await providerSetup.isTrustedProject(providerId: providerId, workingDirectory: workingDirectory) else {
            throw AgentOneShotPromptError.untrustedProject(
                providerId: providerId,
                workingDirectory: workingDirectory
            )
        }
    }

    private func detectedExecutablePath(for providerId: String) async throws -> String {
        if await providerDetection.resolvedPath(for: providerId) == nil {
            await providerDetection.checkProvider(providerId)
        }
        guard let detectedPath = await providerDetection.resolvedPath(for: providerId) else {
            throw AgentError.cliNotInstalled(providerId)
        }
        return detectedPath
    }

    private func oneShotEnvironment(detectedPath: String) -> [String: String] {
        var environment = environmentBuilder.buildEnvironment(providerEnv: nil)
        let executableDirectory = URL(fileURLWithPath: detectedPath).deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? ""
        let pathComponents = existingPath.split(separator: ":").map(String.init)
        if !pathComponents.contains(executableDirectory) {
            environment["PATH"] = ([executableDirectory] + pathComponents).joined(separator: ":")
        }
        return environment
    }

    private static func agentProviderID(_ providerId: String) throws -> AgentCLIKit.AgentProviderID {
        guard let agentProviderID = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            throw AgentOneShotPromptError.failed("Unsupported provider: \(providerId)")
        }
        return agentProviderID
    }

    private static func promptWithReadOnlyProjectGuidance(_ prompt: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return readOnlyProjectGuidance
        }
        return [trimmedPrompt, readOnlyProjectGuidance].joined(separator: "\n\n")
    }

    private static func normalizedModel(_ model: String) -> String? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty,
              trimmedModel != AppSettings.defaultModelValue else {
            return nil
        }
        return trimmedModel
    }

    private static func timeInterval(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1.0e18
    }

    private static func mappedError(_ error: AgentCLIKit.AgentOneShotPromptError) -> AgentOneShotPromptError {
        switch error {
        case .approvalRequired:
            return .approvalRequested
        case .promptRequired:
            return .promptRequired
        case .emptyOutput:
            return .emptyOutput
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case .unsupportedProvider,
             .unsupportedToolPolicy,
             .commandLaunchFailed,
             .commandFailed,
             .unavailableModel,
             .malformedOutput,
             .providerReportedError:
            return .failed(error.localizedDescription)
        }
    }

    private static func mappedDiagnosticError(_ message: String) -> AgentOneShotPromptError? {
        // Some AgentCLIKit one-shot failures can cross actor boundaries as generic localized errors.
        let normalized = message.lowercased()
        guard normalized.contains("one-shot prompt") else {
            return nil
        }
        if normalized.contains("cancelled") {
            return .cancelled
        }
        if normalized.contains("timed out") {
            return .timedOut
        }
        if normalized.contains("requested user approval") ||
            normalized.contains("requested approval") {
            return .approvalRequested
        }
        if normalized.contains("requested user input") ||
            normalized.contains("user input during a one-shot prompt") {
            return .promptRequired
        }
        if normalized.contains("completed without final output") {
            return .emptyOutput
        }
        return nil
    }
}
