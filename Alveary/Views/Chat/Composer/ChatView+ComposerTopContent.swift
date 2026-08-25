import AgentCLIKit
import SwiftUI

extension ChatView {
    var composerTopContentConfiguration: AppKitChatComposerTopContentView.Configuration {
        var items: [AppKitChatComposerTopContentView.Item] = []
        appendProviderAuthenticationNotice(to: &items)
        appendLastTurnError(to: &items)
        appendVoiceInputNotice(to: &items)
        appendSessionContinuityNotice(to: &items)
        appendGoalStatus(to: &items)
        appendStagedContext(to: &items)
        return AppKitChatComposerTopContentView.Configuration(items: items)
    }

    private func appendVoiceInputNotice(to items: inout [AppKitChatComposerTopContentView.Item]) {
        guard let notice = voiceInputCoordinator.notice else {
            return
        }
        let severity: AppKitChatComposerTopContentSeverity = switch notice.severity {
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
        items.append(.inlineBanner(.init(
            message: notice.message,
            severity: severity,
            actionTitle: notice.recovery == nil ? nil : "Open Microphone Settings",
            onAction: notice.recovery.map { recovery in
                { openVoiceInputRecovery(recovery) }
            },
            onDismiss: voiceInputCoordinator.dismissNotice
        )))
    }

    /// Banner for a provider that refused the turn until its credential is renewed.
    ///
    /// First in the list, so it outranks every other composer notice: it is the only one offering a way
    /// out of a state where nothing else will work. The accompanying `.error` becomes the transcript
    /// row rather than a second banner — `shouldPersistErrorEvent` nils `lastTurnError` on that path.
    /// The Sign In action appears only when the registry defines a command for this provider;
    /// otherwise the banner still explains the failure, which is more than the bare error row did.
    private func appendProviderAuthenticationNotice(to items: inout [AppKitChatComposerTopContentView.Item]) {
        guard let message = viewModel.providerAuthenticationFailure else {
            return
        }
        let canSignIn = providerSignIn?.signInCommand(for: providerID) != nil && terminalManager != nil
        items.append(.inlineBanner(.init(
            message: message,
            severity: .error,
            actionTitle: canSignIn ? "Sign In" : nil,
            onAction: canSignIn ? { startProviderSignIn() } : nil,
            onDismiss: { viewModel.providerAuthenticationFailure = nil }
        )))
    }

    /// Opens the sign-in tab and reveals the pane holding it, then clears the banner: the pane is now
    /// what the user is acting in, so leaving the banner up would only be stale.
    private func startProviderSignIn() {
        guard let providerSignIn,
              let terminalManager,
              providerSignIn.startSignIn(providerID: providerID, terminalManager: terminalManager) else {
            return
        }
        appState.showTerminalPane()
        viewModel.providerAuthenticationFailure = nil
    }

    private func appendLastTurnError(to items: inout [AppKitChatComposerTopContentView.Item]) {
        guard let lastTurnError = viewModel.lastTurnError else {
            return
        }
        if viewModel.canRetryFailedSessionHandoff {
            items.append(.inlineBanner(.init(
                message: lastTurnError,
                severity: .error,
                actionTitle: voiceInputCoordinator.isDraftInteractionLocked ? nil : "Retry",
                onAction: voiceInputCoordinator.isDraftInteractionLocked ? nil : {
                    viewModel.retryFailedSessionHandoff()
                },
                onDismiss: nil
            )))
        } else {
            items.append(.inlineBanner(.init(
                message: lastTurnError,
                severity: .error,
                actionTitle: nil,
                onAction: nil,
                onDismiss: { viewModel.lastTurnError = nil }
            )))
        }
    }

    private func appendSessionContinuityNotice(to items: inout [AppKitChatComposerTopContentView.Item]) {
        guard let sessionContinuityNotice = viewModel.sessionContinuityNotice else {
            return
        }
        items.append(.inlineBanner(.init(
            message: sessionContinuityNotice,
            severity: .warning,
            actionTitle: nil,
            onAction: nil,
            onDismiss: { viewModel.sessionContinuityNotice = nil }
        )))
    }

    private func appendGoalStatus(to items: inout [AppKitChatComposerTopContentView.Item]) {
        guard let goal = viewModel.visibleGoalSnapshot else {
            return
        }
        let isTerminal = goal.status.isTerminal
        let restartDisabledTooltip = terminalGoalRestartDisabledTooltip(for: goal)
        items.append(.goalStatus(.init(
            snapshot: goal,
            actionError: viewModel.state.goalActionError,
            onPause: goalActionHandler(.pause, isTerminal: isTerminal, goal: goal),
            onResume: goalActionHandler(.resume, isTerminal: isTerminal, goal: goal),
            onDelete: goalActionHandler(.delete, isTerminal: isTerminal, goal: goal),
            onRestartTerminal: terminalGoalRestartHandler(for: goal),
            isRestartTerminalEnabled: restartDisabledTooltip == nil,
            restartTerminalDisabledTooltip: restartDisabledTooltip,
            onDismissTerminal: isTerminal ? { viewModel.dismissTerminalGoalStatus() } : nil
        )))
    }

    private func goalActionHandler(
        _ action: AgentGoalAction,
        isTerminal: Bool,
        goal: AgentGoalSnapshot
    ) -> (() -> Void)? {
        guard !voiceInputCoordinator.isDraftInteractionLocked,
              !isTerminal,
              goal.availableActions.contains(action),
              isGoalActionVisible(action, for: goal) else {
            return nil
        }
        return {
            Task { try? await viewModel.performGoalAction(action) }
        }
    }

    func isGoalActionVisible(_ action: AgentGoalAction, for goal: AgentGoalSnapshot) -> Bool {
        guard providerID == "claude",
              action == .delete,
              goal.status == .active else {
            return true
        }
        return !viewModel.isAgentActivelyWorking
    }

    private func terminalGoalRestartHandler(for goal: AgentGoalSnapshot) -> (() -> Void)? {
        guard !voiceInputCoordinator.isDraftInteractionLocked,
              goal.status.isComposerRestartableTerminal,
              !viewModel.state.isGoalModeArmed else {
            return nil
        }
        return { prepareVisibleTerminalGoalRestart() }
    }

    private func terminalGoalRestartDisabledTooltip(for goal: AgentGoalSnapshot) -> String? {
        guard goal.status.isComposerRestartableTerminal,
              !viewModel.state.isGoalModeArmed else {
            return nil
        }
        if voiceInputCoordinator.isDraftInteractionLocked {
            return "Finish dictation before restarting this goal."
        }
        return goalModeStartUnavailableMessage()
    }

    private func appendStagedContext(to items: inout [AppKitChatComposerTopContentView.Item]) {
        guard let stagedContext = viewModel.stagedContext else {
            return
        }
        items.append(.stagedContext(.init(
            context: stagedContext,
            onDismiss: voiceInputCoordinator.isDraftInteractionLocked ? nil : {
                viewModel.dismissStagedContext()
            }
        )))
    }
}
