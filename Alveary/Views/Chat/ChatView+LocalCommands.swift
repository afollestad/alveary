import Foundation

extension ChatView {
    @discardableResult
    func handleLocalCommandIfNeeded(draft: ComposerDraft) -> Bool {
        guard let command = ComposerLocalCommandParser.parse(draft.text, availability: localCommandAvailability) else {
            return false
        }

        switch command.kind {
        case .plan:
            handlePlanLocalCommand(command, draft: draft)
        case .handoff:
            handleHandoffLocalCommand(command, draft: draft)
        }
        return true
    }

    private func handlePlanLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        Task {
            var didTogglePlanMode = false
            do {
                let requiredPlanModeEnabled = try await viewModel.togglePlanModeForOutbound()
                didTogglePlanMode = true
                if command.argument.isEmpty {
                    return
                } else {
                    try await viewModel.queueOrSend(command.argument, requiredPlanModeEnabled: requiredPlanModeEnabled)
                }
            } catch {
                let restoredText = didTogglePlanMode && !command.argument.isEmpty ? command.argument : draft.text
                viewModel.replaceInputDraft(restoredText, source: draft.source)
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    private func handleHandoffLocalCommand(_ command: ComposerLocalCommand, draft: ComposerDraft) {
        guard viewModel.triggerSessionHandoffFromCommand(
            steeringPrompt: command.argument.isEmpty ? nil : command.argument
        ) else {
            return
        }
        clearSubmittedDraftAndRequestFocus(source: draft.source)
    }
}
