import AgentCLIKit
import Foundation

/// Validate CLI capabilities and frozen selections before creating a review task or starting paid work.
extension DefaultPullRequestReviewWorkerExecutor {
    private static let capabilityOutputLimitBytes = 256 * 1024
    private static let preflightRunID = "review-worker-preflight"

    /// Recheck each launch: a CLI wrapper's target can change without changing the configured executable path.
    func preflight(_ configuration: ReviewWorkerConfiguration) async throws {
        let harnessID = try Self.validatedHarnessID(configuration)
        if harnessID == .opencode {
            let adapter = try Self.adapter(for: harnessID, executablePath: configuration.executablePath)
            let prepared = try await adapter.prepareOneShotPrompt(request: .init(
                harnessId: harnessID, workingDirectory: FileManager.default.temporaryDirectory,
                prompt: "Validate the frozen review worker configuration.", environment: workerEnvironment(for: harnessID),
                model: configuration.launchModel, effort: AppSettings.openCodeNativeEffort(stored: configuration.effort),
                timeout: Self.timeoutSeconds, toolPolicy: .readOnly
            ))
            try prepared.cleanup()
            return
        }

        let result = try await capabilityOutput(configuration, harnessID: harnessID)
        guard result.succeeded,
              !result.stdoutWasTruncated,
              !result.stderrWasTruncated else {
            throw PullRequestReviewWorkerError.executableUnavailable(configuration.executablePath)
        }
        let help = [result.stdout, result.stderr].joined(separator: "\n")
        let requiredFlags = Self.requiredFlags(for: harnessID)
        let missing = requiredFlags.filter { !help.contains($0) }
        guard missing.isEmpty else {
            throw PullRequestReviewWorkerError.missingCapabilities(
                harnessID: configuration.harnessID,
                flags: missing
            )
        }
    }

    private func capabilityOutput(
        _ configuration: ReviewWorkerConfiguration, harnessID: AgentCLIKit.AgentHarnessID
    ) async throws -> ShellResult {
        let helpArguments = harnessID == .codex ? ["exec", "--help"] : ["--help"]
        let processKey = PullRequestReviewWorkerProcessKey(
            runID: Self.preflightRunID,
            generation: 0,
            executionID: "\(configuration.harnessID):\(configuration.executablePath)"
        )
        let shellRunner = capabilityShellRunner
            ?? DefaultShellRunner(processTracker: processRegistry.tracker(for: processKey))
        do {
            return try await shellRunner.run(
                executable: configuration.executablePath,
                args: helpArguments,
                environment: workerEnvironment(for: harnessID),
                environmentPolicy: .replace,
                processGroupPolicy: .create,
                timeout: .seconds(5),
                stdoutLimitBytes: Self.capabilityOutputLimitBytes,
                stderrLimitBytes: Self.capabilityOutputLimitBytes,
                standardInput: .nullDevice
            )
        } catch let ShellError.ioFailure(failure) {
            try Task.checkCancellation()
            throw ReviewWorkerIOFailure(stage: .capabilityCheck, failure: failure, codexCompletion: nil)
        }
    }

    private static func requiredFlags(for harnessID: AgentCLIKit.AgentHarnessID) -> [String] {
        switch harnessID {
        case .claude:
            [
                "--safe-mode",
                "--no-session-persistence",
                "--restricted",
                "--strict-mcp-config",
                "--disable-slash-commands",
                "--no-chrome",
                "--permission-mode",
                "--permission-prompts",
                "dontAsk",
                "--tools"
            ]
        case .codex:
            [
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--skip-git-repo-check",
                "--strict-config",
                "--disable",
                "--sandbox"
            ]
        case .opencode:
            []
        }
    }

}
