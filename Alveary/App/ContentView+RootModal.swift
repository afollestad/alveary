import SwiftUI

enum ContentViewRootModalKind: Equatable {
    case onboarding
    case imagePreview(UUID)
}

extension ContentView {
    var rootWindowModal: AppWindowModalOverlayPresenter.Modal? {
        _ = voiceInputInteractionLockGeneration
        switch Self.rootWindowModalKind(
            isOnboardingPresented: onboardingViewModel.isPresented,
            imagePreviewRequest: appState.imagePreviewRequest,
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
        case nil:
            return nil
        }
    }

    /// Scheduling proposals are confirmed in the transcript widget, not a root modal.
    static func rootWindowModalKind(
        isOnboardingPresented: Bool,
        imagePreviewRequest: AppImagePreviewRequest?,
        isVoiceInputLocked: Bool = false
    ) -> ContentViewRootModalKind? {
        guard !isVoiceInputLocked else {
            return nil
        }
        if isOnboardingPresented {
            return .onboarding
        }

        return imagePreviewRequest.map { .imagePreview($0.id) }
    }

    func dismissRootWindowModal() {
        switch Self.rootWindowModalKind(
            isOnboardingPresented: onboardingViewModel.isPresented,
            imagePreviewRequest: appState.imagePreviewRequest,
            isVoiceInputLocked: voiceInputLifecycleController.isComposerInteractionLocked
        ) {
        case .onboarding, nil:
            return
        case .imagePreview:
            appState.dismissImagePreview()
        }
    }
}
