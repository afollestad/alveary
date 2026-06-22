import Foundation

protocol AgentOneShotPromptService: Sendable {
    func generate(prompt: String, workingDirectory: String) async throws -> String
}

enum AgentOneShotPromptError: LocalizedError, Equatable {
    case subscriptionUnavailable
    case untrustedProject(providerId: String, workingDirectory: String)
    case approvalRequested
    case emptyOutput
    case interrupted
    case failed(String)
    case cancelled
    case timedOut

    var errorDescription: String? {
        switch self {
        case .subscriptionUnavailable:
            return "Unable to observe the hidden agent response."
        case .untrustedProject(let providerId, let workingDirectory):
            return "Project is not trusted for \(providerId): \(workingDirectory)"
        case .approvalRequested:
            return "Commit message generation requested user approval."
        case .emptyOutput:
            return "Commit message generation returned no message."
        case .interrupted:
            return "Commit message generation was interrupted."
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
    static let syntheticConversationIDPrefix = "one-shot-prompt."

    private let agentsManager: any AgentsManager
    private let settingsService: SettingsService
    private let providerSetup: ProviderSetupService
    private let timeout: Duration

    init(
        agentsManager: any AgentsManager,
        settingsService: SettingsService,
        providerSetup: ProviderSetupService,
        timeout: Duration = .seconds(120)
    ) {
        self.agentsManager = agentsManager
        self.settingsService = settingsService
        self.providerSetup = providerSetup
        self.timeout = timeout
    }

    func generate(prompt: String, workingDirectory: String) async throws -> String {
        let conversationId = Self.syntheticConversationIDPrefix + UUID().uuidString
        let settings = await settingsService.current.normalized()
        let config = Self.makeSpawnConfig(settings: settings, workingDirectory: workingDirectory)

        do {
            let output = try await runGeneration(
                prompt: prompt,
                conversationId: conversationId,
                config: config,
                autoTrust: settings.autoTrustProjects
            )
            await cleanupRuntime(conversationId: conversationId)
            return output
        } catch is CancellationError {
            await cleanupRuntime(conversationId: conversationId)
            throw AgentOneShotPromptError.cancelled
        } catch {
            await cleanupRuntime(conversationId: conversationId)
            if Task.isCancelled {
                throw AgentOneShotPromptError.cancelled
            }
            throw error
        }
    }

    private func runGeneration(
        prompt: String,
        conversationId: String,
        config: AgentSpawnConfig,
        autoTrust: Bool
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await self.runGenerationWithoutTimeout(
                    prompt: prompt,
                    conversationId: conversationId,
                    config: config,
                    autoTrust: autoTrust
                )
            }
            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw AgentOneShotPromptError.timedOut
            }

            guard let output = try await group.next() else {
                throw AgentOneShotPromptError.emptyOutput
            }
            return output
        }
    }

    private func runGenerationWithoutTimeout(
        prompt: String,
        conversationId: String,
        config: AgentSpawnConfig,
        autoTrust: Bool
    ) async throws -> String {
        try Task.checkCancellation()

        await providerSetup.prepareForSpawn(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory,
            autoTrust: autoTrust
        )
        guard await providerSetup.isTrustedProject(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory
        ) else {
            throw AgentOneShotPromptError.untrustedProject(
                providerId: config.providerId,
                workingDirectory: config.workingDirectory
            )
        }

        try await agentsManager.spawn(id: conversationId, config: config, forkSession: false)
        guard let subscription = await agentsManager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            throw AgentOneShotPromptError.subscriptionUnavailable
        }
        try await agentsManager.sendMessage(prompt, conversationId: conversationId, activityVisibility: .hidden)

        return try await collectOutput(from: subscription.stream)
    }

    private func collectOutput(from stream: AsyncStream<ConversationEvent>) async throws -> String {
        var collector = OneShotPromptOutputCollector()

        for await event in stream {
            try Task.checkCancellation()
            if let completed = try collector.handle(event) {
                return completed
            }
        }

        try Task.checkCancellation()
        return try collector.completedOutput()
    }

    private func cleanupRuntime(conversationId: String) async {
        do {
            try await agentsManager.destroyRuntime(conversationId: conversationId)
        } catch {
            // Keep the generation result/error as the authoritative outcome.
        }
    }

    private static func makeSpawnConfig(settings: AppSettings, workingDirectory: String) -> AgentSpawnConfig {
        let model = Self.normalizedModel(settings.defaultModel)

        return AgentSpawnConfig(
            providerId: settings.defaultProvider,
            workingDirectory: CanonicalPath.normalize(workingDirectory),
            permissionMode: settings.permissionMode,
            planModeEnabled: false,
            model: model,
            effort: settings.effort,
            speedMode: .standard,
            initialPrompt: nil
        )
    }

    private static func normalizedModel(_ model: String) -> String? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty,
              trimmedModel != AppSettings.defaultModelValue else {
            return nil
        }
        return trimmedModel
    }
}

private struct OneShotPromptOutputCollector {
    private var output = ""
    private var didObserveSentTurn = false
    private var activeRuntimeTurnId: String?

    mutating func handle(_ event: ConversationEvent) throws -> String? {
        switch event {
        case .sessionInit,
             .providerSessionMetadataChanged,
             .permissionModeChanged,
             .collaborationModeChanged:
            return nil
        case .messageChunk(let text, let parentToolUseId):
            appendRootChunk(text, parentToolUseId: parentToolUseId)
            return nil
        case .message(let role, let content, let parentToolUseId):
            replaceWithRootAssistantMessage(role: role, content: content, parentToolUseId: parentToolUseId)
            return nil
        case .runtimeActivity(let state, let turnId, let outcome):
            return try handleRuntimeActivity(state: state, turnId: turnId, outcome: outcome)
        case .tokens:
            return try handleTokens(event)
        case .toolApprovalRequested,
             .toolApprovalFailed:
            throw AgentOneShotPromptError.approvalRequested
        case .error(let message):
            throw AgentOneShotPromptError.failed(message)
        case .stop(let message):
            if didObserveSentTurn, ConversationInterruption.isDisplayMessage(message) {
                throw AgentOneShotPromptError.interrupted
            }
            return didObserveSentTurn ? try completedOutput() : nil
        default:
            return nil
        }
    }

    func completedOutput() throws -> String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw AgentOneShotPromptError.emptyOutput
        }
        return trimmedOutput
    }

    private mutating func appendRootChunk(_ text: String, parentToolUseId: String?) {
        guard parentToolUseId == nil else {
            return
        }
        didObserveSentTurn = true
        output.append(text)
    }

    private mutating func replaceWithRootAssistantMessage(role: String, content: String, parentToolUseId: String?) {
        guard role == "assistant", parentToolUseId == nil else {
            return
        }
        didObserveSentTurn = true
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output = content
        }
    }

    private mutating func handleRuntimeActivity(
        state: ConversationRuntimeActivityState,
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) throws -> String? {
        switch state {
        case .active:
            didObserveSentTurn = true
            activeRuntimeTurnId = turnId
            return nil
        case .idle:
            guard shouldAcceptRuntimeIdle(turnId: turnId) else {
                return nil
            }
            switch outcome {
            case .unknown, .completed:
                return try completedOutput()
            case .failed(let message):
                throw AgentOneShotPromptError.failed(message)
            case .interrupted:
                throw AgentOneShotPromptError.interrupted
            }
        }
    }

    private func handleTokens(_ event: ConversationEvent) throws -> String? {
        guard didObserveSentTurn,
              let payload = TokenEventPayload(event),
              payload.stopReason != ConversationEvent.interimUsageStopReason,
              payload.completesTurn else {
            return nil
        }
        if ConversationInterruption.isRequestInterruptedByUserReason(payload.stopReason) {
            throw AgentOneShotPromptError.interrupted
        }
        guard !payload.isError, payload.permissionDenials.isEmpty else {
            throw AgentOneShotPromptError.failed(
                ConversationErrorDisplayPolicy.sessionHandoffTokenFailureMessage(stopReason: payload.stopReason)
            )
        }
        return try completedOutput()
    }

    private func shouldAcceptRuntimeIdle(turnId: String?) -> Bool {
        guard didObserveSentTurn else {
            return false
        }
        return activeRuntimeTurnId == nil || turnId == nil || activeRuntimeTurnId == turnId
    }
}
