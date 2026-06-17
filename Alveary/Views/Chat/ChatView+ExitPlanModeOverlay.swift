@preconcurrency import AppKit
import Foundation

private let exitPlanModeOverlayDensity = AppKitComposerOverlayPanelDensity(
    panelPadding: AppKitComposerOverlayMetrics.regularDensity.panelPadding,
    topPadding: AppKitComposerOverlayMetrics.regularDensity.topPadding,
    headerRowsSpacing: AppKitComposerOverlayMetrics.regularDensity.headerRowsSpacing,
    rowSpacing: 0,
    footerSpacing: 4,
    placesFooterInlineWithLastRow: false,
    bottomClearance: 12
)

struct ExitPlanModeOverlayState: Equatable {
    enum Selection: Equatable {
        case implement
        case customDenial
    }

    var selection: Selection = .implement
    var customResponse = ""
    var isSubmitting = false
    var isDismissing = false
    var isHiddenAfterSubmit = false

    var trimmedCustomResponse: String {
        customResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        switch selection {
        case .implement:
            return true
        case .customDenial:
            return !trimmedCustomResponse.isEmpty
        }
    }
}

enum ExitPlanModeOverlayPresentation {
    static func activeApproval(
        pendingApproval: PendingToolApproval?,
        hasActiveAskUserQuestionPrompt: Bool,
        overlayState: ExitPlanModeOverlayState?
    ) -> PendingToolApproval? {
        guard !hasActiveAskUserQuestionPrompt,
              let pendingApproval,
              pendingApproval.request.toolName == "ExitPlanMode",
              !isHiddenAfterSubmit(overlayState) else {
            return nil
        }
        return pendingApproval
    }

    static func composerStatusText(
        pendingApproval: PendingToolApproval?,
        overlayState: ExitPlanModeOverlayState?
    ) -> DeferredToolComposerStatusText? {
        guard let pendingApproval else {
            return nil
        }
        guard pendingApproval.request.toolName == "ExitPlanMode",
              isHiddenAfterSubmit(overlayState) else {
            return pendingApproval.request.composerStatusText
        }
        return nil
    }

    static func isHiddenAfterSubmit(_ state: ExitPlanModeOverlayState?) -> Bool {
        state?.isHiddenAfterSubmit == true
    }
}

extension ChatView {
    var activeExitPlanModeApproval: PendingToolApproval? {
        let pendingApproval = viewModel.state.pendingToolApproval
        return ExitPlanModeOverlayPresentation.activeApproval(
            pendingApproval: pendingApproval,
            hasActiveAskUserQuestionPrompt: activeAskUserQuestionPrompt != nil,
            overlayState: exitPlanModeOverlayState(for: pendingApproval)
        )
    }

    var pendingToolApprovalStatusTextForComposer: DeferredToolComposerStatusText? {
        let pendingApproval = viewModel.state.pendingToolApproval
        return ExitPlanModeOverlayPresentation.composerStatusText(
            pendingApproval: pendingApproval,
            overlayState: exitPlanModeOverlayState(for: pendingApproval)
        )
    }

    var exitPlanModeOverlayConfiguration: AppKitComposerOverlayConfiguration? {
        guard let approval = activeExitPlanModeApproval else {
            return nil
        }

        let state = exitPlanModeOverlayState(for: approval)
        let canInteract = !state.isSubmitting &&
            !state.isDismissing &&
            approval.status == .pending &&
            !viewModel.state.isSendingMessage &&
            !viewModel.state.isReconfiguringSession

        return AppKitComposerOverlayConfiguration(
            id: "exit-plan-mode-\(approval.request.toolUseId)",
            panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: exitPlanModeRows(
                    approval: approval,
                    state: state,
                    canInteract: canInteract
                ),
                density: exitPlanModeOverlayDensity,
                titleFont: .systemFont(ofSize: 14, weight: .semibold),
                primaryTitle: "Submit",
                isPrimaryEnabled: canInteract && state.canSubmit,
                isResolving: !canInteract || state.isSubmitting || state.isDismissing,
                onDismiss: {
                    dismissExitPlanModeApproval(approval)
                },
                onPrimary: {
                    submitExitPlanModeApproval(approval)
                }
            )
        )
    }

    func exitPlanModeRows(
        approval: PendingToolApproval,
        state: ExitPlanModeOverlayState,
        canInteract: Bool
    ) -> [AppKitComposerOverlayOptionRowView.Configuration] {
        return [
            exitPlanModeImplementRow(approval: approval, state: state, canInteract: canInteract),
            exitPlanModeCustomDenialRow(approval: approval, state: state, canInteract: canInteract)
        ]
    }

    func exitPlanModeImplementRow(
        approval: PendingToolApproval,
        state: ExitPlanModeOverlayState,
        canInteract: Bool
    ) -> AppKitComposerOverlayOptionRowView.Configuration {
        AppKitComposerOverlayOptionRowView.Configuration(
            id: "\(approval.request.toolUseId)-implement",
            indexText: "1.",
            title: "Yes, implement this plan",
            isSelected: state.selection == .implement,
            isFocused: state.selection == .implement,
            isEnabled: canInteract,
            fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
            fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
            minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
            verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
            customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
            mouseActivationBehavior: .submitSelection,
            onSelect: {
                updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
                    state.selection = .implement
                }
            },
            onSubmitSelection: {
                submitExitPlanModeSelection(approval, selection: .implement)
            }
        )
    }

    func exitPlanModeCustomDenialRow(
        approval: PendingToolApproval,
        state: ExitPlanModeOverlayState,
        canInteract: Bool
    ) -> AppKitComposerOverlayOptionRowView.Configuration {
        AppKitComposerOverlayOptionRowView.Configuration(
            id: "\(approval.request.toolUseId)-custom-denial",
            indexText: "2.",
            title: "",
            isSelected: state.selection == .customDenial,
            isFocused: state.selection == .customDenial,
            isEnabled: canInteract,
            customPlaceholder: "No, and tell the agent what to do differently",
            customText: state.customResponse,
            fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
            fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
            minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
            verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
            customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
            usesInlineCustomPlaceholder: true,
            onSelect: {
                updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
                    state.selection = .customDenial
                }
            },
            onSubmitSelection: {
                submitExitPlanModeSelection(approval, selection: .customDenial)
            },
            onCustomTextChanged: { text in
                updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
                    state.selection = .customDenial
                    state.customResponse = text
                }
            }
        )
    }

    func exitPlanModeOverlayState(for approval: PendingToolApproval) -> ExitPlanModeOverlayState {
        exitPlanModeOverlayStates[approval.request.toolUseId] ?? ExitPlanModeOverlayState()
    }

    func updateExitPlanModeOverlayState(
        toolUseId: String,
        _ update: (inout ExitPlanModeOverlayState) -> Void
    ) {
        var state = exitPlanModeOverlayStates[toolUseId] ?? ExitPlanModeOverlayState()
        update(&state)
        exitPlanModeOverlayStates[toolUseId] = state
    }

    func submitExitPlanModeSelection(_ approval: PendingToolApproval, selection: ExitPlanModeOverlayState.Selection) {
        updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
            state.selection = selection
        }
        guard exitPlanModeOverlayState(for: approval).canSubmit else {
            return
        }
        submitExitPlanModeApproval(approval)
    }

    func submitExitPlanModeApproval(_ approval: PendingToolApproval) {
        let state = exitPlanModeOverlayState(for: approval)
        guard state.canSubmit else {
            return
        }

        updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
            state.isSubmitting = true
            state.isHiddenAfterSubmit = true
        }
        if state.selection == .customDenial {
            appState.requestComposerFocus()
        }

        Task {
            do {
                switch state.selection {
                case .implement:
                    try await viewModel.approveExitPlanMode(toolUseId: approval.request.toolUseId)
                case .customDenial:
                    try await viewModel.denyExitPlanMode(
                        toolUseId: approval.request.toolUseId,
                        followUp: state.trimmedCustomResponse
                    )
                }
                clearExitPlanModeOverlayStateIfResolved(toolUseId: approval.request.toolUseId)
            } catch {
                updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
                    state.isSubmitting = false
                    state.isHiddenAfterSubmit = false
                }
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Plan response failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func dismissExitPlanModeApproval(_ approval: PendingToolApproval) {
        updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
            state.isDismissing = true
        }

        Task {
            do {
                try await viewModel.denyExitPlanMode(toolUseId: approval.request.toolUseId)
                clearExitPlanModeOverlayStateIfResolved(toolUseId: approval.request.toolUseId)
            } catch {
                updateExitPlanModeOverlayState(toolUseId: approval.request.toolUseId) { state in
                    state.isDismissing = false
                }
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Plan dismiss failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearExitPlanModeOverlayStateIfResolved(toolUseId: String) {
        guard viewModel.state.pendingToolApproval?.request.toolUseId != toolUseId else {
            return
        }
        exitPlanModeOverlayStates[toolUseId] = nil
    }

    func exitPlanModeOverlayState(for approval: PendingToolApproval?) -> ExitPlanModeOverlayState? {
        guard let approval else {
            return nil
        }
        return exitPlanModeOverlayStates[approval.request.toolUseId]
    }
}
