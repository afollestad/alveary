import AgentCLIKit

extension ChatView {
    var composerPresentation: ComposerPresentation {
        ComposerPresentation(
            text: viewModel.state.inputDraft,
            isTextEffectivelyEmpty: viewModel.state.inputDraftIsEffectivelyEmpty,
            mode: composerMode,
            defaultEnterBehavior: defaultEnterBehavior,
            supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
            canSteerCurrentTurn: viewModel.canSteerCurrentTurn,
            isHandoffSteeringPromptActive: viewModel.state.isAwaitingHandoffSteering,
            isHandoffOutputPromptActive: viewModel.state.pendingHandoffOutput != nil,
            handoffSteeringCountdown: viewModel.state.handoffSteeringCountdownRemaining,
            sendCountdown: viewModel.state.handoffCountdownRemaining,
            isProjectTrustBlocked: isProjectTrustBlocked,
            isGoalModeArmed: viewModel.state.isGoalModeArmed
        )
    }

    var localCommandAvailability: ComposerLocalCommandAvailability {
        guard !viewModel.state.hasActiveSessionHandoff else {
            return ComposerLocalCommandAvailability()
        }

        return ComposerLocalCommandAvailability(
            supportsGoalMode: composerCapabilities.supportsGoalMode,
            supportsPlanMode: composerCapabilities.supportsPlanMode,
            supportsSpeedMode: composerCapabilities.supportsSpeedMode,
            supportedEffortOptions: reasoningConfiguration.selection.effortOptions.map(\.value),
            supportsSessionHandoff: true,
            suppressesSlashCommandSuggestions: viewModel.state.isGoalModeArmed
        )
    }

    var passthroughSlashCommands: [ComposerPassthroughSlashCommand] {
        guard providerID == "claude",
              !viewModel.state.hasActiveSessionHandoff else {
            return []
        }

        return [
            ComposerPassthroughSlashCommand(
                command: "compact",
                subtitle: "Compact context",
                detailText: "Claude",
                uri: "alveary://provider-commands/claude/compact",
                argumentHint: "Optional compact instructions"
            )
        ]
    }

    var canUseOutboundComposerActions: Bool {
        if isProjectTrustBlocked || voiceInputCoordinator.isDraftInteractionLocked {
            return false
        }
        switch composerMode {
        case .idle, .busy(canStop: true):
            return true
        case .busy(canStop: false), .progressOnly:
            return false
        }
    }

    var isGoalModeToggleEnabled: Bool {
        goalModeToggleDisabledTooltip == nil
    }

    var planModeToggleDisabledTooltip: String? {
        if viewModel.visibleGoalSnapshot?.status.isTerminal == false {
            return "Plan mode is unavailable while a goal is active."
        }
        return composerCapabilities.planModeDisabledTooltip
    }

    var isPlanModeToggleEnabled: Bool {
        composerCapabilities.supportsPlanMode &&
            planModeToggleDisabledTooltip == nil &&
            !composerPresentation.areControlsDisabled
    }

    var isGoalModeChipVisible: Bool {
        if viewModel.state.isGoalModeArmed {
            return true
        }
        guard let goal = viewModel.visibleGoalSnapshot,
              !goal.status.isTerminal else {
            return false
        }
        return goal.availableActions.contains(.delete) &&
            isGoalActionVisible(.delete, for: goal)
    }

    var isGoalModeChipEnabled: Bool {
        if viewModel.state.isGoalModeArmed {
            return true
        }
        guard let goal = viewModel.visibleGoalSnapshot,
              !goal.status.isTerminal else {
            return false
        }
        return goal.availableActions.contains(.delete) &&
            isGoalActionVisible(.delete, for: goal)
    }

    func dismissGoalModeFromComposerChip() {
        guard !voiceInputCoordinator.isDraftInteractionLocked else {
            return
        }
        if viewModel.state.isGoalModeArmed {
            viewModel.setGoalModeArmed(false)
            return
        }
        guard let goal = viewModel.visibleGoalSnapshot,
              !goal.status.isTerminal,
              goal.availableActions.contains(.delete),
              isGoalActionVisible(.delete, for: goal) else {
            return
        }
        Task { try? await viewModel.performGoalAction(.delete) }
    }

    func setPlanModeFromComposer(_ isEnabled: Bool) {
        guard !voiceInputCoordinator.isDraftInteractionLocked else {
            return
        }
        if isEnabled,
           let unavailableMessage = planModeToggleDisabledTooltip {
            viewModel.lastTurnError = unavailableMessage
            return
        }
        if isEnabled {
            viewModel.setGoalModeArmed(false)
        }
        selectedPlanModeBinding.wrappedValue = isEnabled
    }

    func setGoalModeFromComposer(_ isEnabled: Bool) {
        guard !voiceInputCoordinator.isDraftInteractionLocked else {
            return
        }
        guard isEnabled else {
            viewModel.setGoalModeArmed(false)
            return
        }
        guard let unavailableMessage = goalModeStartUnavailableMessage() else {
            selectedPlanModeBinding.wrappedValue = false
            viewModel.setGoalModeArmed(true)
            return
        }
        viewModel.lastTurnError = unavailableMessage
    }

    var goalModeToggleDisabledTooltip: String? {
        if !composerCapabilities.supportsGoalMode {
            return composerCapabilities.goalModeDisabledTooltip ?? "Goal mode is not supported by this agent."
        }
        if let tooltip = composerCapabilities.goalModeDisabledTooltip {
            return tooltip
        }
        if viewModel.visibleGoalSnapshot?.status.isTerminal == false {
            return "Use the goal status row to manage the active goal."
        }
        if isProjectTrustBlocked {
            return "Approve this project before starting Goal mode."
        }
        if viewModel.hasVisibleUserMessageHistory,
           !composerCapabilities.supportsExistingSessionGoalStart {
            return "This agent can only start Goal mode before the first visible user message."
        }
        if composerPresentation.areControlsDisabled {
            return "Goal mode is unavailable right now."
        }
        return nil
    }

    var showWorktreePicker: Bool {
        threadPresentation.showWorktreePicker
    }

    func clearSubmittedDraftAndRequestFocus(source: ComposerDraftSource) {
        viewModel.clearInputDraft(source: source)
        appState.requestComposerFocus()
    }

}
