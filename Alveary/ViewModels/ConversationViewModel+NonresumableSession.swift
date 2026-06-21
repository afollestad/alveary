import AgentCLIKit
import Foundation
import OSLog
import SwiftData

private let nonresumableSessionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Alveary",
    category: "NonresumableSession"
)

extension ConversationViewModel {
    func prepareRuntimeAndResolveSessionRecoveryContext(
        stagedContextOverride: String?,
        useCurrentStagedContextWhenOverrideNil: Bool,
        respawnSettingsSource: SessionSettingsConfigSource
    ) async throws -> SessionRecoveryStagedContext {
        let recoveryContext = needsSetup
            ? nil
            : try await prepareRuntimeForOutbound(settingsSource: respawnSettingsSource)
        return resolveSessionRecoveryStagedContext(
            recoveryContext: recoveryContext,
            stagedContextOverride: stagedContextOverride,
            useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil
        )
    }

    func recoverHiddenSessionHandoffFromLocalHistoryIfNeeded(_ error: Error) async -> Bool {
        guard isNonresumableProviderSessionError(error) else {
            return false
        }

        let restoreContext = localRestoreContextForNonresumableSession()
            ?? "No local transcript history was available."
        nonresumableSessionLogger.error(
            "Hidden handoff could not resume provider session; using local transcript fallback: \(error.localizedDescription, privacy: .public)"
        )
        state.endTurn()
        let output = SessionHandoffPromptBuilder.localHistoryFallbackOutput(
            restoreContext: restoreContext,
            isPlanModeHandoff: state.sessionHandoffStartedInPlanMode
        )
        await finishHiddenSessionHandoff(with: output)
        return true
    }

    func recoverNonresumableSessionForOutboundIfNeeded(
        _ error: Error,
        config: AgentSpawnConfig
    ) async throws -> String? {
        guard isNonresumableProviderSessionError(error) else {
            throw error
        }

        let restoreContext = localRestoreContextForNonresumableSession()
        nonresumableSessionLogger.error(
            "Provider session could not be resumed; starting fresh session with local context available=\(restoreContext != nil)"
        )
        try await startFreshSessionAfterNonresumableResume(config: config)
        return restoreContext
    }

    func startFreshSessionAfterNonresumableResume(config: AgentSpawnConfig) async throws {
        await flushPendingSaveIfNeeded()
        await prepareForSpawn(config: config)
        try await agentsManager.startFreshSession(conversationId: conversation.id, config: config)
        state.liveSessionConfig = config
        state.runtimeSpeedMode = config.speedMode
        state.sessionContinuityNotice = nil
        resetSubscriptionTrackingForNewSession()
        subscribe()
        recordContextWindowInvalidation()
    }

    func resolveSessionRecoveryStagedContext(
        recoveryContext: String?,
        stagedContextOverride: String?,
        useCurrentStagedContextWhenOverrideNil: Bool
    ) -> SessionRecoveryStagedContext {
        guard let recoveryContext = normalizedStagedContext(recoveryContext) else {
            return SessionRecoveryStagedContext(recoveryContext: nil, stagedContext: stagedContextOverride)
        }

        let currentStagedContext = stagedContextOverride ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil)
        let consumesCurrent = stagedContextOverride == nil && useCurrentStagedContextWhenOverrideNil
        let consumedCurrentContext = consumesCurrent ? currentStagedContext : nil

        guard let currentStagedContext = normalizedStagedContext(currentStagedContext) else {
            return SessionRecoveryStagedContext(
                recoveryContext: recoveryContext,
                stagedContext: recoveryContext,
                consumedCurrentStagedContext: consumedCurrentContext
            )
        }

        if currentStagedContext == dbConversation()?.pendingRestoreContext {
            return SessionRecoveryStagedContext(
                recoveryContext: recoveryContext,
                stagedContext: currentStagedContext,
                consumedCurrentStagedContext: consumedCurrentContext
            )
        }
        if currentStagedContext == recoveryContext {
            return SessionRecoveryStagedContext(
                recoveryContext: recoveryContext,
                stagedContext: currentStagedContext,
                consumedCurrentStagedContext: consumedCurrentContext
            )
        }
        return SessionRecoveryStagedContext(
            recoveryContext: recoveryContext,
            stagedContext: recoveryContext + "\n\n" + currentStagedContext,
            consumedCurrentStagedContext: consumedCurrentContext
        )
    }

    func isNonresumableProviderSessionError(_ error: Error) -> Bool {
        if let error = error as? CodexAppServerError,
           case let .jsonRPCError(method, code, message) = error {
            return isNonresumableProviderSessionError(method: method, code: code, message: message)
        }

        let description = error.localizedDescription
        let isCodexNoRollout = description.localizedCaseInsensitiveContains("codex app server request 'thread/resume' failed") &&
            description.localizedCaseInsensitiveContains("no rollout found")
        let isMissingResumeTarget = description.localizedCaseInsensitiveContains("resume") &&
            (
                description.localizedCaseInsensitiveContains("no conversation found") ||
                    description.localizedCaseInsensitiveContains("conversation not found") ||
                    description.localizedCaseInsensitiveContains("session not found")
            )
        return isCodexNoRollout || isMissingResumeTarget
    }

    func isNonresumableProviderSessionError(method: String, code: Int?, message: String) -> Bool {
        method == "thread/resume" &&
            code == -32600 &&
            message.localizedCaseInsensitiveContains("no rollout found")
    }

    func localRestoreContextForNonresumableSession() -> String? {
        guard let dbConversation = dbConversation() else {
            return nil
        }

        let conversationID = conversation.id
        let records = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.conversationId == conversationID },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )) ?? dbConversation.events
        return dbConversation.restoreContext(from: records)
    }
}

struct SessionRecoveryStagedContext {
    let recoveryContext: String?
    let stagedContext: String?
    let consumedCurrentStagedContext: String?

    init(
        recoveryContext: String?,
        stagedContext: String?,
        consumedCurrentStagedContext: String? = nil
    ) {
        self.recoveryContext = recoveryContext
        self.stagedContext = stagedContext
        self.consumedCurrentStagedContext = consumedCurrentStagedContext
    }
}

private func normalizedStagedContext(_ context: String?) -> String? {
    guard let context else {
        return nil
    }
    let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
