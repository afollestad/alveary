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
        if isProjectTrustBlocked {
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
