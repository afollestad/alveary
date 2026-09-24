import AgentCLIKit
import Foundation

protocol AgentOneShotPromptService: Sendable {
    func generate(prompt: String, workingDirectory: String) async throws -> String
}

enum AgentOneShotPromptError: LocalizedError, Equatable {
    case untrustedProject(harnessId: String, workingDirectory: String)
    case approvalRequested
    case promptRequired
    case emptyOutput
    case failed(String)
    case cancelled
    case timedOut

    var errorDescription: String? {
        switch self {
        case .untrustedProject(let harnessId, let workingDirectory):
            return "Project is not trusted for \(harnessId): \(workingDirectory)"
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
    private let harnessSetup: HarnessSetupService
    private let harnessDetection: HarnessDetectionService
    private let environmentBuilder: AgentEnvironmentBuilder
    private let timeout: Duration

    init(
        promptRunner: any AgentCLIKit.AgentOneShotPromptRunning,
        settingsService: SettingsService,
        harnessSetup: HarnessSetupService,
        harnessDetection: HarnessDetectionService,
        environmentBuilder: AgentEnvironmentBuilder,
        timeout: Duration = .seconds(120)
    ) {
        self.promptRunner = promptRunner
        self.settingsService = settingsService
        self.harnessSetup = harnessSetup
        self.harnessDetection = harnessDetection
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
        let harnessId = settings.effectiveUtilityHarness
        guard HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: harnessId) else {
            throw AgentOneShotPromptError.failed(HarnessFeaturePolicy.unavailableUtilityMessage(harnessID: harnessId))
        }
        guard settings.isHarnessEnabled(harnessId) else {
            throw AgentOneShotPromptError.failed(
                "The commit and pull request generation harness is disabled. "
                    + "Enable it in Harnesses or choose another under Commit & PR generation in Git settings."
            )
        }
        let model = Self.normalizedModel(settings.effectiveUtilityModel)
        guard harnessId != "opencode" || model != nil else {
            throw AgentOneShotPromptError.failed(
                "Commit and pull request generation requires a concrete model. "
                    + "Choose an available OpenCode model under Commit & PR generation in Git settings."
            )
        }
        let normalizedWorkingDirectory = CanonicalPath.normalize(workingDirectory)

        try await prepareTrustedProject(
            harnessId: harnessId,
            workingDirectory: normalizedWorkingDirectory,
            autoTrust: settings.autoTrustProjects
        )

        let detectedPath = try await detectedExecutablePath(for: harnessId)
        let arguments = ClaudeNativeSchedulingLaunchPolicy.arguments(
            harnessID: harnessId,
            configuredArguments: []
        )
        let environment = ClaudeNativeSchedulingLaunchPolicy.environment(
            harnessID: harnessId,
            baseEnvironment: oneShotEnvironment(detectedPath: detectedPath)
        )

        return AgentCLIKit.AgentOneShotPromptRequest(
            harnessId: try Self.agentHarnessID(harnessId),
            workingDirectory: URL(fileURLWithPath: normalizedWorkingDirectory, isDirectory: true),
            prompt: Self.promptWithReadOnlyProjectGuidance(prompt),
            arguments: arguments,
            environment: environment,
            model: model,
            effort: harnessId == "opencode"
                ? AppSettings.openCodeNativeEffort(stored: settings.effectiveUtilityEffort) : settings.effectiveUtilityEffort,
            timeout: Self.timeInterval(from: timeout),
            toolPolicy: .readOnly
        )
    }

    private func prepareTrustedProject(
        harnessId: String,
        workingDirectory: String,
        autoTrust: Bool
    ) async throws {
        await harnessSetup.prepareForSpawn(
            harnessId: harnessId,
            workingDirectory: workingDirectory,
            autoTrust: autoTrust
        )
        guard await harnessSetup.isTrustedProject(harnessId: harnessId, workingDirectory: workingDirectory) else {
            throw AgentOneShotPromptError.untrustedProject(
                harnessId: harnessId,
                workingDirectory: workingDirectory
            )
        }
    }

    private func detectedExecutablePath(for harnessId: String) async throws -> String {
        if await harnessDetection.resolvedPath(for: harnessId) == nil {
            await harnessDetection.checkHarness(harnessId)
        }
        guard let detectedPath = await harnessDetection.resolvedPath(for: harnessId) else {
            throw AgentError.cliNotInstalled(harnessId)
        }
        return detectedPath
    }

    private func oneShotEnvironment(detectedPath: String) -> [String: String] {
        var environment = environmentBuilder.buildEnvironment(harnessEnv: nil)
        let executableDirectory = URL(fileURLWithPath: detectedPath).deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? ""
        let pathComponents = existingPath.split(separator: ":").map(String.init)
        if !pathComponents.contains(executableDirectory) {
            environment["PATH"] = ([executableDirectory] + pathComponents).joined(separator: ":")
        }
        return environment
    }

    private static func agentHarnessID(_ harnessId: String) throws -> AgentCLIKit.AgentHarnessID {
        guard let agentHarnessID = AgentCLIKit.AgentHarnessID(rawValue: harnessId) else {
            throw AgentOneShotPromptError.failed("Unsupported harness: \(harnessId)")
        }
        return agentHarnessID
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
        case .unsupportedHarness,
             .unsupportedToolPolicy,
             .commandLaunchFailed,
             .commandFailed,
             .cleanupFailed,
             .unavailableModel,
             .malformedOutput,
             .harnessReportedError:
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
