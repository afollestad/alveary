import SwiftUI

extension ChatView {
    /// Takes the usage summary rather than reading it. The summary derives from the `@Query`-backed
    /// events, and callers outside a render pass — tests, action closures — have no view hierarchy
    /// to resolve that query in. `composerPanelConfiguration` supplies it for rendering.
    ///
    /// Non-optional on purpose: a `nil` summary tells `Configuration` to hide the context indicator,
    /// and `ChatView` has no such case — its derivation falls back to `.unreported`.
    func composerActionRowConfiguration(
        usageSummary: ConversationUsageSummary
    ) -> ChatComposerActionRowView.Configuration {
        let presentation = composerPresentation
        return ChatComposerActionRowView.Configuration(
            reasoning: reasoningConfiguration,
            supportedPermissionModes: supportedPermissionModeOptions,
            selectedPermissionMode: selectedPermissionModeBinding.wrappedValue,
            showWorktreePicker: showWorktreePicker,
            selectedUseWorktree: selectedUseWorktreeBinding.wrappedValue,
            isPlanModeEnabled: selectedPlanModeBinding.wrappedValue,
            isPlanModeToggleEnabled: isPlanModeToggleEnabled,
            planModeDisabledTooltip: planModeToggleDisabledTooltip,
            isGoalModeArmed: viewModel.state.isGoalModeArmed,
            isGoalModeToggleEnabled: isGoalModeToggleEnabled,
            goalModeDisabledTooltip: goalModeToggleDisabledTooltip,
            isGoalModeChipVisible: isGoalModeChipVisible,
            isGoalModeChipEnabled: isGoalModeChipEnabled,
            usageSummary: usageSummary,
            areControlsDisabled: presentation.areControlsDisabled || voiceInputCoordinator.isDraftInteractionLocked,
            mode: composerMode,
            primaryActionTitle: presentation.primaryActionTitle,
            primaryActionSystemImage: presentation.primaryActionSystemImage,
            isPrimaryActionDisabled: presentation.isPrimaryActionDisabled || voiceInputCoordinator.isDraftInteractionLocked,
            isStopConfirmationArmed: isStopConfirmationArmed,
            composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
            onPermissionModeChange: { selectedPermissionModeBinding.wrappedValue = $0 },
            onUseWorktreeChange: { selectedUseWorktreeBinding.wrappedValue = $0 },
            onPlanModeChange: { setPlanModeFromComposer($0) },
            onGoalModeChange: { setGoalModeFromComposer($0) },
            onGoalModeChipDismiss: {
                dismissGoalModeFromComposerChip()
            },
            taskWorkspace: composerTaskWorkspaceConfiguration,
            voiceInput: voiceInputButtonConfiguration,
            reasoningMenuPresentationRequest: reasoningMenuRequestState.pendingRequest,
            onReasoningMenuRequestConsumed: { consumedRequestID in
                reasoningMenuRequestState.consume(consumedRequestID)
            },
            onSubmit: { submitDraftFromComposer(presentation: presentation) },
            onStop: {
                isStopConfirmationArmed = false
                Task { await viewModel.cancel() }
            },
            appShotAttachment: composerAppShotAttachment,
            // Only raises the trigger; the app root observes it and owns capture routing.
            onAttachAppShot: { appShotCoordinator?.requestCapture() }
        )
    }
}

private extension ChatView {
    var supportedPermissionModeOptions: [ChatComposerActionRowView.PermissionOptionPresentation] {
        ChatComposerPermissionPresentation.options(
            providerID: reasoningConfiguration.selection.providerID,
            permissionModes: composerCapabilities.supportedPermissionModes
        )
    }

    var composerTaskWorkspaceConfiguration: ChatComposerActionRowView.TaskWorkspaceConfiguration? {
        conversation.thread?.taskWorkspaceDescriptor.map { workspace in
            ChatComposerActionRowView.TaskWorkspaceConfiguration(
                primaryRoot: workspace.primaryRoot,
                grantedRoots: workspace.grantedRoots,
                ownershipStrategy: workspace.ownershipStrategy,
                canEdit: viewModel.canEditTaskWorkspaceConfiguration && !voiceInputCoordinator.isDraftInteractionLocked,
                disabledTooltip: viewModel.taskWorkspaceConfigurationDisabledReason,
                onAddFolders: { folders in
                    guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                    viewModel.addTaskWorkspaceGrants(folders)
                },
                onRemoveGrant: { folder in
                    guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                    viewModel.removeTaskWorkspaceGrant(folder)
                }
            )
        }
    }

    func submitDraftFromComposer(presentation: ComposerPresentation) {
        guard presentation.canSubmit,
              !voiceInputCoordinator.isDraftInteractionLocked else {
            return
        }
        sendDraft()
    }
}
