import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func refreshAgentCLIKitStatus(conversationId: String, services: AgentCLIKitHostServices) async {
        guard let status = await services.runtime.status(conversationId: services.hostAdapter.conversationId(conversationId)) else {
            return
        }
        applyAgentCLIKitStatus(status, conversationId: conversationId)
    }

    func startAgentCLIKitStatusTask(conversationId: String, services: AgentCLIKitHostServices) {
        agentCLIKitStatusTasks[conversationId]?.cancel()
        agentCLIKitStatusTasks[conversationId] = Task { [weak self] in
            let statuses = await services.runtime.statusUpdates(
                conversationId: services.hostAdapter.conversationId(conversationId)
            )
            for await status in statuses {
                await self?.applyAgentCLIKitStatus(status, conversationId: conversationId)
            }
        }
    }

    func refreshStatus(conversationId: String) async -> ActivitySignal {
        let runtimeConversationId = agentCLIKitServices.hostAdapter.conversationId(conversationId)
        if let status = await agentCLIKitServices.runtime.status(conversationId: runtimeConversationId) {
            applyAgentCLIKitStatus(status, conversationId: conversationId)
        }
        return self.status(for: conversationId)
    }

    private func applyAgentCLIKitStatus(_ status: AgentCLIKit.AgentRuntimeStatus, conversationId: String) {
        guard shouldApplyAgentCLIKitStatus(status, conversationId: conversationId) else {
            return
        }
        let ignoresStaleActiveStatus = shouldIgnoreStaleActiveStatus(status, conversationId: conversationId)
        agentCLIKitStatuses[conversationId] = status
        if ignoresStaleActiveStatus {
            eventBuffers[conversationId]?.lastKnownRuntimeTurnActive = false
        } else {
            handleRuntimeTurnActiveStatus(status, conversationId: conversationId)
        }
        syncRuntimeSettingsStatus(status, conversationId: conversationId)
        syncRuntimeGoalStatus(status.goal, conversationId: conversationId)
        processSnapshot.withLock { $0 = [] }
        publishManagedProcessesChanged()
        if suppressCancelledInteractionStatusIfNeeded(status, conversationId: conversationId) {
            return
        }
        guard let signal = agentCLIKitActivitySignal(
            for: status,
            conversationId: conversationId,
            ignoresStaleActiveStatus: ignoresStaleActiveStatus
        ) else {
            return
        }
        updateStatus(signal, for: conversationId)
    }

    private func agentCLIKitActivitySignal(
        for status: AgentCLIKit.AgentRuntimeStatus,
        conversationId: String,
        ignoresStaleActiveStatus: Bool
    ) -> ActivitySignal? {
        switch status.waitingState {
        case .approval, .prompt, .planModeExit:
            return .waitingForUser
        case .idle:
            return idleAgentCLIKitActivitySignal(
                for: status,
                conversationId: conversationId,
                ignoresStaleActiveStatus: ignoresStaleActiveStatus
            )
        }
    }

    private func idleAgentCLIKitActivitySignal(
        for status: AgentCLIKit.AgentRuntimeStatus,
        conversationId: String,
        ignoresStaleActiveStatus: Bool
    ) -> ActivitySignal? {
        switch status.state {
        case .starting, .running:
            if status.isTurnActive && !ignoresStaleActiveStatus {
                return .busy
            }
            return self.status(for: conversationId) == .error ? nil : .idle
        case .exited, .cancelled:
            if eventBuffers[conversationId]?.hasDeferredToolStop == true,
               self.status(for: conversationId) == .waitingForUser {
                return nil
            }
            return .idle
        case .failed:
            return .error
        }
    }

    private func shouldApplyAgentCLIKitStatus(_ status: AgentCLIKit.AgentRuntimeStatus, conversationId: String) -> Bool {
        guard let existing = agentCLIKitStatuses[conversationId],
              existing.generation == status.generation else {
            return true
        }
        return status.lastEventIndex >= existing.lastEventIndex
    }

    private func shouldIgnoreStaleActiveStatus(_ status: AgentCLIKit.AgentRuntimeStatus, conversationId: String) -> Bool {
        guard status.isTurnActive,
              let latestTerminalRuntimeEventIndex = eventBuffers[conversationId]?.latestTerminalRuntimeEventIndex else {
            return false
        }
        return status.lastEventIndex <= latestTerminalRuntimeEventIndex
    }

    private func syncRuntimeSettingsStatus(_ status: AgentCLIKit.AgentRuntimeStatus, conversationId: String) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let state = conversationState(for: conversationId)
            if let permissionMode = status.permissionMode {
                if permissionMode == "plan" {
                    state.runtimePlanModeEnabled = true
                } else {
                    state.runtimePermissionMode = permissionMode
                    state.lastNonPlanPermissionMode = permissionMode
                }
            }
            if let collaborationMode = status.collaborationMode {
                state.runtimePlanModeEnabled = collaborationMode == .plan
            }
        }
    }

    private func syncRuntimeGoalStatus(_ goal: AgentCLIKit.AgentGoalSnapshot?, conversationId: String) {
        guard let goal else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let state = conversationState(for: conversationId)
            state.goalSnapshot = goal
            if !goal.status.isTerminal {
                state.dismissedTerminalGoalKeys.removeAll()
            }
        }
    }
}
