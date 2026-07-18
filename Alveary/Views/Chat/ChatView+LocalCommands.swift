import AgentCLIKit
import Foundation

extension ChatView {
    @discardableResult
    func handleLocalCommandIfNeeded(draft: ComposerDraft) -> Bool {
        guard let command = ComposerLocalCommandParser.parse(draft.text, availability: localCommandAvailability) else {
            return false
        }

        switch command.kind {
        case .goal:
            handleGoalLocalCommand(command, draft: draft)
        case .plan:
            handlePlanLocalCommand(command, draft: draft)
        case .fast:
            handleFastLocalCommand(command, draft: draft)
        case .effort:
            handleEffortLocalCommand(command, draft: draft)
        case .handoff:
            handleHandoffLocalCommand(command, draft: draft)
        }
        return true
    }

    @discardableResult
    func handleComposerGoalOrLocalControlIfNeeded(draft: ComposerDraft) -> Bool {
        if handleExactGoalActionCommandIfNeeded(draft: draft) {
            return true
        }
        if handleArmedGoalSubmitIfNeeded(draft: draft) {
            return true
        }
        if handleLocalCommandIfNeeded(draft: draft) {
            return true
        }
        return false
    }

    @discardableResult
    func handleExactGoalActionCommandIfNeeded(draft: ComposerDraft) -> Bool {
        guard let command = Self.exactGoalCommand(for: draft.text) else {
            return false
        }
        let shouldClearDraft = shouldClearDraftForExactGoalCommand(command)
        if shouldClearDraft {
            clearSubmittedDraftAndRequestFocus(source: draft.source)
        }
        performExactGoalCommand(
            command,
            restartSeedDraft: shouldClearDraft ? ComposerDraft(text: "", source: draft.source, isEffectivelyEmpty: true) : nil
        )
        return true
    }

    @discardableResult
    func handleArmedGoalSubmitIfNeeded(draft: ComposerDraft) -> Bool {
        guard viewModel.state.isGoalModeArmed else {
            return false
        }
        guard !draft.isEffectivelyEmpty else {
            return false
        }

        if let command = ComposerLocalCommandParser.parse(
            draft.text,
            availability: ComposerLocalCommandAvailability(supportsGoalMode: true)
        ),
           command.kind == .goal,
           command.argument.isEmpty {
            clearSubmittedDraftAndRequestFocus(source: draft.source)
            viewModel.setGoalModeArmed(false)
            return true
        }

        submitGoalObjective(draft.messageText, restoreText: draft.text, source: draft.source)
        return true
    }

    private func handleGoalLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        let normalizedArgument = command.argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if command.argument.isEmpty {
            clearSubmittedDraftAndRequestFocus(source: draft.source)
            toggleGoalModeFromCommand()
            return
        }

        if let exactCommand = Self.exactGoalCommand(forArgument: normalizedArgument) {
            let shouldClearDraft = shouldClearDraftForExactGoalCommand(exactCommand)
            if shouldClearDraft {
                clearSubmittedDraftAndRequestFocus(source: draft.source)
            }
            performExactGoalCommand(
                exactCommand,
                restartSeedDraft: shouldClearDraft ? ComposerDraft(text: "", source: draft.source, isEffectivelyEmpty: true) : nil
            )
            return
        }

        submitGoalObjective(command.argument, restoreText: command.argument, source: draft.source)
    }

    private func toggleGoalModeFromCommand() {
        if viewModel.state.isGoalModeArmed {
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

    private func submitGoalObjective(_ objective: String, restoreText: String, source: ComposerDraftSource) {
        guard let unavailableMessage = goalModeStartUnavailableMessage() else {
            clearSubmittedDraftAndRequestFocus(source: source)
            requestScrollToBottom()
            Task {
                do {
                    try await viewModel.ensurePlanModeForOutbound(false)
                    try await viewModel.startGoal(
                        objective,
                        supportsExistingSessionGoalStart: composerCapabilities.supportsExistingSessionGoalStart
                    )
                } catch {
                    viewModel.replaceInputDraft(restoreText, source: source)
                    if viewModel.pendingPlanModeForDisplay() ?? viewModel.effectivePlanModeEnabled {
                        viewModel.setGoalModeArmed(false)
                    } else {
                        viewModel.setGoalModeArmed(true)
                    }
                    if viewModel.lastTurnError == nil {
                        viewModel.lastTurnError = error.localizedDescription
                    }
                }
            }
            return
        }
        viewModel.lastTurnError = unavailableMessage
    }

    func goalModeStartUnavailableMessage() -> String? {
        if !composerCapabilities.supportsGoalMode {
            return composerCapabilities.goalModeDisabledTooltip ?? "Goal mode is not supported by this agent."
        }
        if let tooltip = composerCapabilities.goalModeDisabledTooltip {
            return tooltip
        }
        if viewModel.visibleGoalSnapshot?.status.isTerminal == false {
            return "A goal is already active."
        }
        if isProjectTrustBlocked {
            return "Approve this project before starting Goal mode."
        }
        if viewModel.hasVisibleUserMessageHistory,
           !composerCapabilities.supportsExistingSessionGoalStart {
            return "This agent can only start Goal mode before the first visible user message."
        }
        if viewModel.state.messageQueue.peekNext() != nil {
            return "Send or clear queued messages before starting Goal mode."
        }
        if viewModel.state.isAwaitingHandoffSteering {
            return "Complete session handoff steering before starting Goal mode."
        }
        if viewModel.state.isReconfiguringSession {
            return "Session changes are still being applied."
        }
        if viewModel.state.isSendingMessage {
            return "Another message is already being sent."
        }
        if viewModel.isAgentActivelyWorking {
            return "Wait for the current turn to finish before starting Goal mode."
        }
        return nil
    }

    func prepareVisibleTerminalGoalRestart(seedDraft: ComposerDraft? = nil) {
        guard let goal = viewModel.visibleGoalSnapshot,
              goal.status.isComposerRestartableTerminal else {
            viewModel.state.goalActionError = "No blocked goal is available to restart."
            appState.requestComposerFocus()
            return
        }
        if viewModel.state.isGoalModeArmed {
            viewModel.state.goalActionError = nil
            appState.requestComposerFocus()
            return
        }

        let draft = seedDraft ?? viewModel.flushDraftFromEditor()
        guard let unavailableMessage = goalModeStartUnavailableMessage() else {
            selectedPlanModeBinding.wrappedValue = false
            viewModel.setGoalModeArmed(true)
            viewModel.state.goalActionError = nil
            if draft.isEffectivelyEmpty {
                viewModel.replaceInputDraft(goal.objective, source: draft.source)
            }
            viewModel.dismissTerminalGoalStatus()
            appState.requestComposerFocus()
            return
        }

        viewModel.state.goalActionError = unavailableMessage
    }

    private func performExactGoalCommand(_ command: ExactGoalCommand, restartSeedDraft: ComposerDraft?) {
        switch command {
        case .restart:
            prepareVisibleTerminalGoalRestart(seedDraft: restartSeedDraft)
        case .action(.resume) where viewModel.visibleGoalSnapshot?.status.isComposerRestartableTerminal == true:
            prepareVisibleTerminalGoalRestart(seedDraft: restartSeedDraft)
        case .action(let action):
            performGoalActionFromCommand(action)
        }
    }

    private func shouldClearDraftForExactGoalCommand(_ command: ExactGoalCommand) -> Bool {
        guard viewModel.state.isGoalModeArmed else {
            return true
        }
        switch command {
        case .restart:
            return false
        case .action(.resume) where viewModel.visibleGoalSnapshot?.status.isComposerRestartableTerminal == true:
            return false
        case .action:
            return true
        }
    }

    private func performGoalActionFromCommand(_ action: AgentGoalAction) {
        Task {
            try? await viewModel.performGoalAction(action)
        }
    }

    private static func exactGoalCommand(for text: String) -> ExactGoalCommand? {
        guard let command = ComposerLocalCommandParser.parse(
            text,
            availability: ComposerLocalCommandAvailability()
        ),
              command.kind == .goal else {
            return nil
        }
        return exactGoalCommand(forArgument: command.argument)
    }

    private static func exactGoalCommand(forArgument argument: String) -> ExactGoalCommand? {
        switch argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "clear":
            return .action(.delete)
        case "pause":
            return .action(.pause)
        case "resume":
            return .action(.resume)
        case "restart":
            return .restart
        default:
            return nil
        }
    }

    private func handlePlanLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        let targetPlanModeEnabled = !(viewModel.pendingPlanModeForDisplay() ?? viewModel.effectivePlanModeEnabled)
        if targetPlanModeEnabled,
           let unavailableMessage = planModeToggleDisabledTooltip {
            viewModel.lastTurnError = unavailableMessage
            return
        }
        if targetPlanModeEnabled {
            viewModel.setGoalModeArmed(false)
        }
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        Task {
            var didTogglePlanMode = false
            do {
                let requiredPlanModeEnabled = try await viewModel.togglePlanModeForOutbound()
                didTogglePlanMode = true
                if command.argument.isEmpty {
                    return
                } else {
                    try await viewModel.queueOrSend(
                        command.argument,
                        requiredPlanModeEnabled: requiredPlanModeEnabled,
                        supportsLocalImageInput: composerCapabilities.supportsLocalImageInput
                    )
                }
            } catch {
                let restoredText = didTogglePlanMode && !command.argument.isEmpty ? command.argument : draft.text
                viewModel.replaceInputDraft(restoredText, source: draft.source)
                restoreLocalCommandDraftAttachmentsIfNeeded(draft)
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    private func handleFastLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        Task {
            var didEnableFastMode = false
            do {
                try await viewModel.ensureSpeedModeEnabledForOutbound(supportsSpeedMode: composerCapabilities.supportsSpeedMode)
                didEnableFastMode = true
                if command.argument.isEmpty {
                    return
                } else {
                    try await viewModel.queueOrSend(
                        command.argument,
                        requiredSpeedMode: .fast,
                        supportsLocalImageInput: composerCapabilities.supportsLocalImageInput
                    )
                }
            } catch {
                let restoredText = didEnableFastMode && !command.argument.isEmpty ? command.argument : draft.text
                viewModel.replaceInputDraft(restoredText, source: draft.source)
                restoreLocalCommandDraftAttachmentsIfNeeded(draft)
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    private func handleEffortLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        let supportedEffortOptions = localCommandAvailability.supportedEffortOptions
        guard !supportedEffortOptions.isEmpty else {
            return
        }
        guard !command.argument.isEmpty else {
            viewModel.clearInputDraft(source: draft.source)
            reasoningMenuRequestState.requestPresentation()
            return
        }

        let requestedEffort = command.argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let canonicalEffort = supportedEffortOptions.first(where: {
            $0.caseInsensitiveCompare(requestedEffort) == .orderedSame
        }) else {
            viewModel.lastTurnError = "Effort must be one of: \(supportedEffortOptions.joined(separator: "|"))."
            return
        }

        guard reasoningConfiguration.onEffortChange(canonicalEffort) else {
            if viewModel.lastTurnError == nil {
                viewModel.lastTurnError = "Effort cannot be changed right now."
            }
            return
        }
        clearSubmittedDraftAndRequestFocus(source: draft.source)
    }

    private func handleHandoffLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        guard viewModel.triggerSessionHandoffFromCommand(
            steeringPrompt: command.argument.isEmpty ? nil : command.argument
        ) else {
            return
        }
        clearSubmittedDraftAndRequestFocus(source: draft.source)
    }

    private func restoreLocalCommandDraftAttachmentsIfNeeded(_ draft: ComposerDraft) {
        var didRestoreAttachments = false
        if viewModel.state.stagedImageAttachments.isEmpty {
            viewModel.state.stagedImageAttachments = draft.attachments
            didRestoreAttachments = true
        }
        if viewModel.state.stagedFileAttachments.isEmpty {
            viewModel.state.stagedFileAttachments = draft.fileAttachments
            didRestoreAttachments = true
        }
        if viewModel.state.stagedAppShots.isEmpty {
            viewModel.state.stagedAppShots = draft.appShots
            didRestoreAttachments = true
        }
        if didRestoreAttachments {
            viewModel.refreshInputDraftEffectiveEmptyForAttachments()
        }
    }
}

private enum ExactGoalCommand {
    case action(AgentGoalAction)
    case restart
}
