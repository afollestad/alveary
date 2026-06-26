import Foundation

extension ChatView {
    func sendDraft() {
        guard canUseOutboundComposerActions else {
            return
        }

        let draft = viewModel.flushDraftFromEditor()
        if handleComposerGoalOrLocalControlIfNeeded(draft: draft) {
            return
        }

        let steeringMessage = draft.isEffectivelyEmpty ? "" : draft.text
        if viewModel.submitSessionHandoffSteeringPrompt(steeringMessage) {
            appState.requestComposerFocus()
            return
        }

        guard !draft.isEffectivelyEmpty else {
            return
        }

        let isSessionHandoffDraft = viewModel.prepareManualSessionHandoffSendIfNeeded()
        requestScrollToBottom()
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        sendSubmittedDraft(draft, isSessionHandoffDraft: isSessionHandoffDraft)
    }

    func steerDraft() {
        guard canUseOutboundComposerActions, !viewModel.state.isNormalSteeringBlockedBySessionHandoff else {
            return
        }

        let draft = viewModel.flushDraftFromEditor()
        if handleComposerGoalOrLocalControlIfNeeded(draft: draft) {
            return
        }

        sendSteeringDraft(draft)
    }

    func alternateSteerDraft() {
        guard canUseOutboundComposerActions, !viewModel.state.isNormalSteeringBlockedBySessionHandoff else {
            return
        }

        let draft = viewModel.flushDraftFromEditor()
        if handleComposerGoalOrLocalControlIfNeeded(draft: draft) {
            return
        }

        if draft.isEffectivelyEmpty {
            guard viewModel.messageQueue.peekNext() != nil else {
                return
            }
            Task { try? await viewModel.steerNextQueuedMessage() }
            return
        }

        sendSteeringDraft(draft)
    }

    func sendSteeringDraft(_ draft: ComposerDraft) {
        guard !viewModel.state.isNormalSteeringBlockedBySessionHandoff, !draft.isEffectivelyEmpty else {
            return
        }

        requestScrollToBottom()
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        Task {
            do {
                try await viewModel.steer(
                    draft.messageText,
                    supportsLocalImageInput: composerCapabilities.supportsLocalImageInput
                )
            } catch {
                restoreDraftAfterSendFailure(draft)
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Steer failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func requestScrollToBottom() {
        isFollowing = true
        scrollToBottomRequest += 1
    }

    private func sendSubmittedDraft(_ draft: ComposerDraft, isSessionHandoffDraft: Bool) {
        let retryableMessageCount = viewModel.state.retryableFailedMessageIDs.count
        Task {
            do {
                viewModel.normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: composerCapabilities.supportsSpeedMode)
                if isSessionHandoffDraft {
                    try await viewModel.sendSessionHandoffOutput(draft.messageText)
                } else {
                    try await viewModel.queueOrSend(
                        draft.messageText,
                        supportsLocalImageInput: composerCapabilities.supportsLocalImageInput
                    )
                }
            } catch is CancellationError {
                // User-initiated cancellation already restores the draft during rollback.
            } catch {
                if viewModel.state.retryableFailedMessageIDs.count == retryableMessageCount {
                    restoreDraftAfterSendFailure(draft)
                }
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    private func restoreDraftAfterSendFailure(_ draft: ComposerDraft) {
        viewModel.replaceInputDraft(draft.text, source: draft.source)
        restoreStagedAttachmentsIfNeeded(draft)
    }

    private func restoreStagedAttachmentsIfNeeded(_ draft: ComposerDraft) {
        if viewModel.state.stagedImageAttachments.isEmpty {
            viewModel.state.stagedImageAttachments = draft.attachments
            viewModel.refreshInputDraftEffectiveEmptyForAttachments()
        }
        if viewModel.state.stagedAppShots.isEmpty {
            viewModel.state.stagedAppShots = draft.appShots
            viewModel.refreshInputDraftEffectiveEmptyForAttachments()
        }
    }
}
