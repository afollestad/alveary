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
    case unsupportedHarness(String)
    case executableUnavailable(String)
    case missingCapabilities(harnessID: String, flags: [String])
    case capabilityCheckFailed(harnessID: String, exitCode: Int32, message: String)
    case unsafeCommand(String)
    case duplicateExecution(String)
    case outputTooLarge
    case commandFailed(harnessID: String, exitCode: Int32, message: String)
    case emptyOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .unsafeCommand(let message):
            message
        case .unsupportedHarness(let harnessID):
            HarnessFeaturePolicy.unavailableReviewMessage(harnessID: harnessID)
        case .executableUnavailable(let path):
            "The review worker executable is unavailable: \(path)"
        case .missingCapabilities(let harnessID, let flags):
            "The \(harnessID) CLI does not support required review worker flags: \(flags.joined(separator: ", "))"
        case .capabilityCheckFailed(let harnessID, let exitCode, let message):
            "The \(harnessID) CLI capability check exited with code \(exitCode). \(message)"
        case .duplicateExecution(let executionID):
            "Review worker execution is already active: \(executionID)"
        case .outputTooLarge:
            "The review worker output exceeded its size limit."
        case .commandFailed(let harnessID, let exitCode, let message):
            "The \(harnessID) review worker exited with code \(exitCode). \(message)"
        case .emptyOutput(let harnessID):
            "The \(harnessID) review worker returned no output."
        }
    }
}

/// Runs app-configured isolated review workers against app-minted packet leases.
actor DefaultPullRequestReviewWorkerExecutor: PullRequestReviewWorkerExecuting {
    /// Deep reviews of large diffs can outlast twenty minutes, and a kill discards the worker's paid work; a hung worker only
    /// delays a run the user can cancel. OpenCode stays bounded by AgentCLIKit's shorter credential-validity `executionDeadline`.
    static let timeoutSeconds: TimeInterval = 60 * 60
    static let missingDiagnostic = "No harness diagnostic was returned."
    private static let stdoutLimitBytes = 16 * 1024 * 1024
    private static let stderrLimitBytes = 2 * 1024 * 1024
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
    let processRegistry: PullRequestReviewWorkerProcessRegistry
    let capabilityShellRunner: (any ShellRunner)?
    private let executionShellRunner: (any ShellRunner)?
    private var tasksByRunID: [String: [String: Task<String, Error>]] = [:]

    init(
        environmentBuilder: any AgentEnvironmentBuilder,
        processRegistry: PullRequestReviewWorkerProcessRegistry,
        capabilityShellRunner: (any ShellRunner)? = nil,
        executionShellRunner: (any ShellRunner)? = nil
    ) {
        self.environmentBuilder = environmentBuilder
        self.processRegistry = processRegistry
        self.capabilityShellRunner = capabilityShellRunner
        self.executionShellRunner = executionShellRunner
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
        // Native preparation performs its own isolated compatibility and model checks immediately before launch.
        if try Self.validatedHarnessID(configuration) != .opencode { try await preflight(configuration) }

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
        let harnessID = try Self.validatedHarnessID(configuration)
        let adapter = try Self.adapter(for: harnessID, executablePath: configuration.executablePath)
        let request = AgentCLIKit.AgentOneShotPromptRequest(
            harnessId: harnessID,
            workingDirectory: packet.directoryURL,
            prompt: prompt,
            arguments: harnessID == .claude ? Self.claudeArguments : [],
            environment: workerEnvironment(for: harnessID),
            model: configuration.launchModel,
            effort: harnessID == .opencode ? AppSettings.openCodeNativeEffort(stored: configuration.effort) : configuration.effort,
            timeout: Self.timeoutSeconds,
            toolPolicy: .readOnly
        )
        let prepared = try await adapter.prepareOneShotPrompt(request: request)
        let outcome: Result<String, Error>
        do {
            // Native preparation awaits external probes; the packet must still own this path when paid work starts.
            if harnessID == .opencode { try await Task.detached { try packet.validate() }.value }
            let command = try Self.isolatedCommand(
                prepared.command, configuration: configuration, packet: packet, prompt: prompt, harnessID: harnessID
            )
            outcome = .success(try await runPrepared(
                prepared, command: command, request: request, adapter: adapter, processKey: processKey
            ))
        } catch { outcome = .failure(error) }
        do { try prepared.cleanup() } catch {
            let failure = if case .failure(let original) = outcome { original.localizedDescription } else { String?.none }
            throw AgentCLIKit.AgentOneShotPromptError.cleanupFailed(
                harnessId: harnessID, reason: error.localizedDescription, operationFailure: failure
            )
        }
        return try outcome.get()
    }

    private func runPrepared(
        _ prepared: AgentCLIKit.AgentPreparedOneShotPrompt,
        command: AgentCLIKit.ShellCommand,
        request: AgentCLIKit.AgentOneShotPromptRequest,
        adapter: any AgentCLIKit.AgentHarnessAdapter,
        processKey: PullRequestReviewWorkerProcessKey
    ) async throws -> String {
        let remaining = prepared.executionDeadline?.timeIntervalSinceNow ?? Self.timeoutSeconds
        guard remaining > 0 else {
            throw AgentCLIKit.AgentOneShotPromptError.timedOut(harnessId: request.harnessId, timeout: 0)
        }
        let shellRunner = executionShellRunner ?? DefaultShellRunner(processTracker: processRegistry.tracker(for: processKey))
        let result: ShellResult
        do {
            result = try await shellRunner.run(
                executable: command.executable,
                args: command.arguments,
                in: command.workingDirectory?.path,
                environment: command.environment,
                environmentPolicy: .replace,
                processGroupPolicy: .create,
                timeout: .seconds(min(Self.timeoutSeconds, remaining)),
                stdoutLimitBytes: Self.stdoutLimitBytes,
                stderrLimitBytes: Self.stderrLimitBytes,
                standardInput: command.standardInput.map(ShellStandardInput.text) ?? .nullDevice
            )
        } catch let ShellError.ioFailure(failure) {
            try Task.checkCancellation()
            let assessment = request.harnessId == .codex ? ReviewWorkerCodexCompletion.assess(failure) : nil
            guard assessment == .recoverable else {
                throw ReviewWorkerIOFailure(stage: .execution, failure: failure, codexCompletion: assessment)
            }
            result = failure.result
        }
        try Task.checkCancellation()
        return try await finalText(
            from: result,
            request: request,
            adapter: adapter
        )
    }

    private func finalText(
        from result: ShellResult,
        request: AgentCLIKit.AgentOneShotPromptRequest,
        adapter: any AgentCLIKit.AgentHarnessAdapter
    ) async throws -> String {
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else {
            throw PullRequestReviewWorkerError.outputTooLarge
        }
        guard result.succeeded else {
            let diagnostic = await failureDiagnostic(from: result, request: request, adapter: adapter)
            throw PullRequestReviewWorkerError.commandFailed(
                harnessID: request.harnessId.rawValue,
                exitCode: result.exitCode,
                message: ReviewTeamDiagnostics.persisted(diagnostic)
            )
        }
        let rawText = try await adapter.finalOneShotPromptText(
            stdout: result.stdout,
            stderr: result.stderr,
            request: request
        )
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PullRequestReviewWorkerError.emptyOutput(request.harnessId.rawValue)
        }
        return text
    }

    /// Harnesses can exit unsuccessfully with an empty stderr and report the cause only in stdout, such as Claude's terminal
    /// `result` frame. Stderr is joined here rather than passed to the adapter, so a classified message never repeats it.
    private func failureDiagnostic(
        from result: ShellResult,
        request: AgentCLIKit.AgentOneShotPromptRequest,
        adapter: any AgentCLIKit.AgentHarnessAdapter
    ) async -> String {
        let reported = await adapter.reportedOneShotPromptFailure(stdout: result.stdout, stderr: "", request: request)?
            .reportedMessage
        var parts: [String] = []
        for part in [reported, result.stderr].compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            where !part.isEmpty && !parts.contains(part) {
            parts.append(part)
        }
        return parts.isEmpty ? Self.missingDiagnostic : parts.joined(separator: "\n")
    }

    static func validatedHarnessID(
        _ configuration: ReviewWorkerConfiguration
    ) throws -> AgentCLIKit.AgentHarnessID {
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
        guard HarnessFeaturePolicy.supportsIsolatedReviewWorkers(harnessID: configuration.harnessID),
              let harnessID = AgentCLIKit.AgentHarnessID(rawValue: configuration.harnessID) else {
            throw PullRequestReviewWorkerError.unsupportedHarness(configuration.harnessID)
        }
        guard configuration.executablePath.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: configuration.executablePath) else {
            throw PullRequestReviewWorkerError.executableUnavailable(configuration.executablePath)
        }
        return harnessID
    }

    static func adapter(
        for harnessID: AgentCLIKit.AgentHarnessID,
        executablePath: String
    ) throws -> any AgentCLIKit.AgentHarnessAdapter {
        switch harnessID {
        case .claude:
            AgentCLIKit.ClaudeHarnessAdapter(configuration: .init(
                executablePath: executablePath,
                enableHooks: false
            ))
        case .codex:
            AgentCLIKit.CodexHarnessAdapter(configuration: .init(executablePath: executablePath))
        case .opencode:
            AgentCLIKit.OpenCodeHarnessAdapter(configuration: .init(executablePath: executablePath))
        }
    }

    private static func isolatedCommand(
        _ command: AgentCLIKit.ShellCommand,
        configuration: ReviewWorkerConfiguration,
        packet: ReviewPacketLease,
        prompt: String,
        harnessID: AgentCLIKit.AgentHarnessID
    ) throws -> AgentCLIKit.ShellCommand {
        var arguments = command.arguments
        guard command.executable == configuration.executablePath,
              command.workingDirectory?.standardizedFileURL == packet.directoryURL.standardizedFileURL,
              command.standardInput == prompt else {
            throw PullRequestReviewWorkerError.unsafeCommand("Review worker launch identity did not match its frozen configuration.")
        }
        switch harnessID {
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
        case .opencode:
            return try isolatedOpenCodeCommand(command)
        }
        return AgentCLIKit.ShellCommand(
            executable: command.executable,
            arguments: arguments,
            environment: command.environment,
            workingDirectory: command.workingDirectory,
            standardInput: command.standardInput
        )
    }

    private static func isolatedOpenCodeCommand(_ command: AgentCLIKit.ShellCommand) throws -> AgentCLIKit.ShellCommand {
        guard !command.inheritsEnvironment else {
            throw PullRequestReviewWorkerError.unsafeCommand("OpenCode review worker environment was not isolated.")
        }
        return command
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

    func workerEnvironment(for harnessID: AgentCLIKit.AgentHarnessID) -> [String: String] {
        let source = environmentBuilder.buildEnvironment(harnessEnv: nil)
        // The SDK copies only the selected provider's connection into its disposable OpenCode profile.
        if harnessID == .opencode { return source }
        let harnessKeys = harnessID == .claude ? Self.claudeEnvironmentKeys : Self.codexEnvironmentKeys
        var result = source.filter { key, _ in
            Self.commonEnvironmentKeys.contains(key)
                || harnessKeys.contains(key)
        }
        let processEnvironment = ProcessInfo.processInfo.environment
        for key in harnessKeys where result[key] == nil {
            result[key] = processEnvironment[key]
        }
        return ClaudeOneShotLaunchPolicy.environment(harnessID: harnessID.rawValue, baseEnvironment: result)
    }
}
