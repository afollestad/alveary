import SwiftUI

enum ContentViewRootModalKind: Equatable {
    case onboarding
    case imagePreview(UUID)
    case scheduledTaskProposal(String)
}

extension ContentView {
    var rootWindowModal: AppWindowModalOverlayPresenter.Modal? {
        _ = voiceInputInteractionLockGeneration
        switch Self.rootWindowModalKind(
            isOnboardingPresented: onboardingViewModel.isPresented,
            imagePreviewRequest: appState.imagePreviewRequest,
            scheduledTaskProposalID: scheduledTaskProposalQueueCoordinator.currentProposal?.id,
            isVoiceInputLocked: voiceInputLifecycleController.isComposerInteractionLocked
        ) {
        case .onboarding:
            return AppWindowModalOverlayPresenter.Modal(
                id: "app-onboarding",
                dismissPolicy: .nonDismissible,
                content: AnyView(AppOnboardingOverlay(viewModel: onboardingViewModel))
            )
        case .imagePreview:
            guard let request = appState.imagePreviewRequest else {
                return nil
            }
            return AppWindowModalOverlayPresenter.Modal(
                id: "image-preview-\(request.id)",
                content: AnyView(
                    AppImagePreviewOverlay(
                        request: request,
                        onDismiss: appState.dismissImagePreview
                    )
                )
            )
        case .scheduledTaskProposal:
            guard let proposal = scheduledTaskProposalQueueCoordinator.currentProposal else {
                return nil
            }
            return AppWindowModalOverlayPresenter.Modal(
                id: Self.scheduledTaskProposalModalID(
                    proposalID: proposal.id,
                    conflictMessage: proposal.conflictMessage
                ),
                content: AnyView(
                    ScheduledTaskProposalOverlay(
                        proposal: proposal,
                        coordinator: scheduledTaskProposalQueueCoordinator,
                        scheduledTasksViewModel: scheduledTasksViewModel
                    )
                )
            )
        case nil:
            return nil
        }
    }

    static func rootWindowModalKind(
        isOnboardingPresented: Bool,
        imagePreviewRequest: AppImagePreviewRequest?,
        scheduledTaskProposalID: String? = nil,
        isVoiceInputLocked: Bool = false
    ) -> ContentViewRootModalKind? {
        guard !isVoiceInputLocked else {
            return nil
        }
        if isOnboardingPresented {
            return .onboarding
        }

        if let imagePreviewRequest {
            return .imagePreview(imagePreviewRequest.id)
        }

        return scheduledTaskProposalID.map(ContentViewRootModalKind.scheduledTaskProposal)
    }

    static func scheduledTaskProposalModalID(
        proposalID: String,
        conflictMessage: String?
    ) -> String {
        "scheduled-task-proposal-\(proposalID)-\(conflictMessage ?? "ready")"
    }

    func dismissRootWindowModal() {
        switch Self.rootWindowModalKind(
            isOnboardingPresented: onboardingViewModel.isPresented,
            imagePreviewRequest: appState.imagePreviewRequest,
            scheduledTaskProposalID: scheduledTaskProposalQueueCoordinator.currentProposal?.id,
            isVoiceInputLocked: voiceInputLifecycleController.isComposerInteractionLocked
        ) {
        case .onboarding, nil:
            return
        case .imagePreview:
            appState.dismissImagePreview()
        case .scheduledTaskProposal(let proposalID):
            scheduledTaskProposalQueueCoordinator.reject(
                proposalID: proposalID,
                clearingProposalErrorIn: scheduledTasksViewModel
            )
        }
    }
}
