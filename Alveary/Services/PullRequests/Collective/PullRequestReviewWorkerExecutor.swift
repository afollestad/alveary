import AgentCLIKit
import Foundation

protocol PullRequestReviewWorkerExecuting: Sendable {
    func preflight(_ configuration: ReviewWorkerConfiguration) async throws
    // swiftlint:disable:next function_parameter_count
    func execute(
        configuration: ReviewWorkerConfiguration,
        packet: ReviewPacketLease,
        prompt: String,
        runID: String,
        generation: Int,
        executionID: String
    ) async throws -> String
    func cancel(runID: String) async
}

enum PullRequestReviewWorkerError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case unsupportedProvider(String)
    case executableUnavailable(String)
    case missingCapabilities(providerID: String, flags: [String])
    case unsafeCommand(String)
    case duplicateExecution(String)
    case outputTooLarge
    case commandFailed(providerID: String, exitCode: Int32, message: String)
    case emptyOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .unsafeCommand(let message):
            message
        case .unsupportedProvider(let providerID):
            "Unsupported review worker provider: \(providerID)"
        case .executableUnavailable(let path):
            "The review worker executable is unavailable: \(path)"
        case .missingCapabilities(let providerID, let flags):
            "The \(providerID) CLI does not support required review worker flags: \(flags.joined(separator: ", "))"
        case .duplicateExecution(let executionID):
            "Review worker execution is already active: \(executionID)"
        case .outputTooLarge:
            "The review worker output exceeded its size limit."
        case .commandFailed(let providerID, let exitCode, let message):
            "The \(providerID) review worker exited with code \(exitCode). \(message)"
        case .emptyOutput(let providerID):
            "The \(providerID) review worker returned no output."
        }
    }
}

/// Runs only app-configured, sessionless review workers against app-minted packet leases.
actor DefaultPullRequestReviewWorkerExecutor: PullRequestReviewWorkerExecuting {
    /// High-effort reviewers can remain active beyond fifteen minutes while inspecting the packet.
    private static let timeout = Duration.seconds(20 * 60)
    private static let stdoutLimitBytes = 16 * 1024 * 1024
    private static let stderrLimitBytes = 2 * 1024 * 1024
    private static let capabilityOutputLimitBytes = 256 * 1024
    private static let preflightRunID = "review-worker-preflight"
    private static let claudeArguments = [
        "--restricted",
        "--strict-mcp-config",
        "--permission-prompts", "none",
        "--disable-slash-commands",
        "--no-chrome"
    ]
    private static let claudeForbiddenArguments: Set<String> = [
        "--add-dir", "--agent", "--agents", "--allowedTools", "--allowed-tools", "--chrome", "--continue",
        "--allow-dangerously-skip-permissions", "--dangerously-skip-permissions", "--mcp-config", "--plugin-dir",
        "--plugin-url", "--resume", "--setting-sources", "--settings"
    ]
    private static let codexArguments = [
        "--ignore-user-config",
        "--ignore-rules",
        "--skip-git-repo-check",
        "--strict-config",
        "-c", "mcp_servers={}",
        "--disable", "apps",
        "--disable", "browser_use",
        "--disable", "computer_use",
        "--disable", "hooks",
        "--disable", "image_generation",
        "--disable", "multi_agent",
        "--disable", "plugins",
        "--disable", "standalone_web_search",
        "--disable", "web_search_request"
    ]
    private static let codexForbiddenArguments: Set<String> = [
        "--add-dir", "--approve-for-me", "--dangerously-bypass-approvals-and-sandbox", "--enable", "--local-provider",
        "--oss", "--profile", "--search", "--worktree", "fork", "resume", "review"
    ]
    private static let commonEnvironmentKeys: Set<String> = [
        "COLORTERM", "HOME", "HTTP_PROXY", "HTTPS_PROXY", "LANG", "NO_PROXY", "ALL_PROXY",
        "PATH", "REQUESTS_CA_BUNDLE", "SSL_CERT_FILE", "TERM", "TERM_PROGRAM", "TMPDIR", "USER"
    ]
    private static let claudeEnvironmentKeys: Set<String> = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "AWS_ACCESS_KEY_ID", "AWS_DEFAULT_REGION",
        "AWS_PROFILE", "AWS_REGION", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
        "ANTHROPIC_BASE_URL", "ANTHROPIC_BEDROCK_BASE_URL", "ANTHROPIC_CUSTOM_HEADERS",
        "ANTHROPIC_VERTEX_BASE_URL", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_FOUNDRY", "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK", "CLAUDE_STREAM_IDLE_TIMEOUT_MS",
        "GOOGLE_APPLICATION_CREDENTIALS", "VERTEX_LOCATION", "VERTEX_PROJECT"
    ]
    private static let codexEnvironmentKeys: Set<String> = [
        "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_ENDPOINT", "CODEX_HOME", "OPENAI_API_KEY",
        "OPENAI_BASE_URL", "OPENAI_ORG_ID"
    ]

    private let environmentBuilder: any AgentEnvironmentBuilder
    private let processRegistry: PullRequestReviewWorkerProcessRegistry
    private let capabilityShellRunner: (any ShellRunner)?
    private var tasksByRunID: [String: [String: Task<String, Error>]] = [:]

    init(
        environmentBuilder: any AgentEnvironmentBuilder,
        processRegistry: PullRequestReviewWorkerProcessRegistry,
        capabilityShellRunner: (any ShellRunner)? = nil
    ) {
        self.environmentBuilder = environmentBuilder
        self.processRegistry = processRegistry
        self.capabilityShellRunner = capabilityShellRunner
    }

    /// Recheck each launch: a CLI wrapper's target can change without changing the configured executable path.
    func preflight(_ configuration: ReviewWorkerConfiguration) async throws {
        let providerID = try Self.validatedProviderID(configuration)
        guard configuration.executablePath.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: configuration.executablePath) else {
            throw PullRequestReviewWorkerError.executableUnavailable(configuration.executablePath)
        }

        let helpArguments = providerID == .codex ? ["exec", "--help"] : ["--help"]
        let processKey = PullRequestReviewWorkerProcessKey(
            runID: Self.preflightRunID,
            generation: 0,
            executionID: "\(configuration.providerID):\(configuration.executablePath)"
        )
        let shellRunner = capabilityShellRunner
            ?? DefaultShellRunner(processTracker: processRegistry.tracker(for: processKey))
        let result = try await shellRunner.run(
            executable: configuration.executablePath,
            args: helpArguments,
            environment: workerEnvironment(for: providerID),
            environmentPolicy: .replace,
            processGroupPolicy: .create,
            timeout: .seconds(5),
            stdoutLimitBytes: Self.capabilityOutputLimitBytes,
            stderrLimitBytes: Self.capabilityOutputLimitBytes,
            standardInput: .nullDevice
        )
        guard result.succeeded,
              !result.stdoutWasTruncated,
              !result.stderrWasTruncated else {
            throw PullRequestReviewWorkerError.executableUnavailable(configuration.executablePath)
        }
        let help = [result.stdout, result.stderr].joined(separator: "\n")
        let requiredFlags = Self.requiredFlags(for: providerID)
        let missing = requiredFlags.filter { !help.contains($0) }
        guard missing.isEmpty else {
            throw PullRequestReviewWorkerError.missingCapabilities(
                providerID: configuration.providerID,
                flags: missing
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    func execute(
        configuration: ReviewWorkerConfiguration,
        packet: ReviewPacketLease,
        prompt: String,
        runID: String,
        generation: Int,
        executionID: String
    ) async throws -> String {
        guard packet.runID == runID,
              !runID.isEmpty,
              generation >= 0,
              !executionID.isEmpty,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PullRequestReviewWorkerError.invalidConfiguration("Review worker execution parameters are invalid.")
        }
        guard tasksByRunID[runID]?[executionID] == nil else {
            throw PullRequestReviewWorkerError.duplicateExecution(executionID)
        }
        try await preflight(configuration)

        let key = PullRequestReviewWorkerProcessKey(
            runID: runID,
            generation: generation,
            executionID: executionID
        )
        let task = Task { [self] in
            try await run(configuration: configuration, packet: packet, prompt: prompt, processKey: key)
        }
        tasksByRunID[runID, default: [:]][executionID] = task
        defer {
            tasksByRunID[runID]?[executionID] = nil
            if tasksByRunID[runID]?.isEmpty == true {
                tasksByRunID[runID] = nil
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel(runID: String) async {
        let tasks = tasksByRunID.removeValue(forKey: runID).map { Array($0.values) } ?? []
        tasks.forEach { $0.cancel() }
        await processRegistry.cancel(runID: runID)
    }

    private func run(
        configuration: ReviewWorkerConfiguration,
        packet: ReviewPacketLease,
        prompt: String,
        processKey: PullRequestReviewWorkerProcessKey
    ) async throws -> String {
        try Task.checkCancellation()
        try await Task.detached { try packet.validate() }.value
        let providerID = try Self.validatedProviderID(configuration)
        let adapter = Self.adapter(for: providerID, executablePath: configuration.executablePath)
        let request = AgentCLIKit.AgentOneShotPromptRequest(
            providerId: providerID,
            workingDirectory: packet.directoryURL,
            prompt: prompt,
            arguments: providerID == .claude ? Self.claudeArguments : [],
            environment: workerEnvironment(for: providerID),
            model: configuration.launchModel,
            effort: configuration.effort,
            timeout: nil,
            toolPolicy: .readOnly
        )
        let baseCommand = try await adapter.makeOneShotPromptCommand(request: request)
        let command = try Self.isolatedCommand(
            baseCommand,
            configuration: configuration,
            packet: packet,
            prompt: prompt,
            providerID: providerID
        )
        let shellRunner = DefaultShellRunner(processTracker: processRegistry.tracker(for: processKey))
        let standardInput = command.standardInput.map(ShellStandardInput.text) ?? .nullDevice
        let result = try await shellRunner.run(
            executable: command.executable,
            args: command.arguments,
            in: command.workingDirectory?.path,
            environment: command.environment,
            environmentPolicy: .replace,
            processGroupPolicy: .create,
            timeout: Self.timeout,
            stdoutLimitBytes: Self.stdoutLimitBytes,
            stderrLimitBytes: Self.stderrLimitBytes,
            standardInput: standardInput
        )
        return try await finalText(
            from: result,
            configuration: configuration,
            request: request,
            adapter: adapter
        )
    }

    private func finalText(
        from result: ShellResult,
        configuration: ReviewWorkerConfiguration,
        request: AgentCLIKit.AgentOneShotPromptRequest,
        adapter: any AgentCLIKit.AgentProviderAdapter
    ) async throws -> String {
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else {
            throw PullRequestReviewWorkerError.outputTooLarge
        }
        guard result.succeeded else {
            // Stdout is a provider event stream and may contain intermediate reasoning or tool content.
            let diagnostic = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = diagnostic.isEmpty ? "No provider diagnostic was returned." : diagnostic
            throw PullRequestReviewWorkerError.commandFailed(
                providerID: configuration.providerID,
                exitCode: result.exitCode,
                message: ReviewTeamDiagnostics.persisted(message)
            )
        }
        let rawText = try await adapter.finalOneShotPromptText(
            stdout: result.stdout,
            stderr: result.stderr,
            request: request
        )
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PullRequestReviewWorkerError.emptyOutput(configuration.providerID)
        }
        return text
    }

    private static func validatedProviderID(
        _ configuration: ReviewWorkerConfiguration
    ) throws -> AgentCLIKit.AgentProviderID {
        guard configuration.id == configuration.id.trimmingCharacters(in: .whitespacesAndNewlines),
              !configuration.id.isEmpty,
              configuration.modelOptionID == configuration.modelOptionID.trimmingCharacters(in: .whitespacesAndNewlines),
              !configuration.modelOptionID.isEmpty,
              configuration.launchModel == configuration.launchModel.trimmingCharacters(in: .whitespacesAndNewlines),
              !configuration.launchModel.isEmpty,
              configuration.launchModel.lowercased() != AppSettings.defaultModelValue,
              configuration.effort == configuration.effort.trimmingCharacters(in: .whitespacesAndNewlines),
              !configuration.effort.isEmpty else {
            throw PullRequestReviewWorkerError.invalidConfiguration(
                "Review workers require an id, exact model option, launch model, and effort."
            )
        }
        guard let providerID = AgentCLIKit.AgentProviderID(rawValue: configuration.providerID) else {
            throw PullRequestReviewWorkerError.unsupportedProvider(configuration.providerID)
        }
        return providerID
    }

    private static func adapter(
        for providerID: AgentCLIKit.AgentProviderID,
        executablePath: String
    ) -> any AgentCLIKit.AgentProviderAdapter {
        switch providerID {
        case .claude:
            AgentCLIKit.ClaudeProviderAdapter(configuration: .init(
                executablePath: executablePath,
                enableHooks: false
            ))
        case .codex:
            AgentCLIKit.CodexProviderAdapter(configuration: .init(executablePath: executablePath))
        }
    }

    private static func isolatedCommand(
        _ command: AgentCLIKit.ShellCommand,
        configuration: ReviewWorkerConfiguration,
        packet: ReviewPacketLease,
        prompt: String,
        providerID: AgentCLIKit.AgentProviderID
    ) throws -> AgentCLIKit.ShellCommand {
        var arguments = command.arguments
        guard command.executable == configuration.executablePath,
              command.workingDirectory?.standardizedFileURL == packet.directoryURL.standardizedFileURL,
              command.standardInput == prompt else {
            throw PullRequestReviewWorkerError.unsafeCommand("Review worker launch identity did not match its frozen configuration.")
        }
        switch providerID {
        case .claude:
            try replaceOption("--permission-mode", with: "dontAsk", in: &arguments)
            guard arguments.contains("--safe-mode"),
                  arguments.contains("--no-session-persistence"),
                  arguments.contains("--restricted"),
                  arguments.contains("--strict-mcp-config"),
                  arguments.contains("--disable-slash-commands"),
                  arguments.contains("--no-chrome"),
                  !arguments.contains(where: Self.claudeForbiddenArguments.contains),
                  !arguments.contains("--fallback-model"),
                  optionValue("--permission-mode", in: arguments) == "dontAsk",
                  optionValue("--permission-prompts", in: arguments) == "none",
                  optionValue("--model", in: arguments) == configuration.launchModel,
                  optionValue("--effort", in: arguments) == configuration.effort,
                  Self.optionValue("--tools", in: arguments) == "Read,Grep,Glob,LS" else {
                throw PullRequestReviewWorkerError.unsafeCommand("Claude review worker safety flags were not applied.")
            }
        case .codex:
            guard let execIndex = arguments.firstIndex(of: "exec") else {
                throw PullRequestReviewWorkerError.unsafeCommand("Codex review worker command did not use exec mode.")
            }
            arguments.insert(contentsOf: codexArguments, at: arguments.index(after: execIndex))
            guard execIndex == arguments.startIndex,
                  !arguments.contains(where: Self.codexForbiddenArguments.contains),
                  arguments.contains("--ephemeral"),
                  Self.optionValue("--sandbox", in: arguments) == "read-only",
                  arguments.contains("approval_policy=\"never\""),
                  Self.optionValue("-C", in: arguments) == packet.directoryURL.path,
                  Self.optionValue("-m", in: arguments) == configuration.launchModel,
                  arguments.contains("model_reasoning_effort=\"\(configuration.effort)\"") else {
                throw PullRequestReviewWorkerError.unsafeCommand("Codex review worker safety flags were not applied.")
            }
        }
        return AgentCLIKit.ShellCommand(
            executable: command.executable,
            arguments: arguments,
            environment: command.environment,
            workingDirectory: command.workingDirectory,
            standardInput: command.standardInput
        )
    }

    private static func replaceOption(_ option: String, with value: String, in arguments: inout [String]) throws {
        guard let index = arguments.lastIndex(of: option),
              arguments.indices.contains(arguments.index(after: index)) else {
            throw PullRequestReviewWorkerError.unsafeCommand("Review worker option was not applied: \(option)")
        }
        arguments[arguments.index(after: index)] = value
    }

    private static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: option),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    private static func requiredFlags(for providerID: AgentCLIKit.AgentProviderID) -> [String] {
        switch providerID {
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
        }
    }

    private func workerEnvironment(for providerID: AgentCLIKit.AgentProviderID) -> [String: String] {
        let source = environmentBuilder.buildEnvironment(providerEnv: nil)
        let providerKeys = providerID == .claude ? Self.claudeEnvironmentKeys : Self.codexEnvironmentKeys
        var result = source.filter { key, _ in
            Self.commonEnvironmentKeys.contains(key)
                || providerKeys.contains(key)
        }
        let processEnvironment = ProcessInfo.processInfo.environment
        for key in providerKeys where result[key] == nil {
            result[key] = processEnvironment[key]
        }
        return result
    }
}
