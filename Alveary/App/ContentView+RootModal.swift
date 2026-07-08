import SwiftUI

enum ContentViewRootModalKind: Equatable {
    case onboarding
    case imagePreview(UUID)
}

extension ContentView {
    var rootWindowModal: AppWindowModalOverlayPresenter.Modal? {
        switch Self.rootWindowModalKind(
            isOnboardingPresented: onboardingViewModel.isPresented,
            imagePreviewRequest: appState.imagePreviewRequest
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

    static func rootWindowModalKind(
        isOnboardingPresented: Bool,
        imagePreviewRequest: AppImagePreviewRequest?
    ) -> ContentViewRootModalKind? {
        if isOnboardingPresented {
            return .onboarding
        }

        return imagePreviewRequest.map { .imagePreview($0.id) }
    }

    func dismissRootWindowModal() {
        guard !onboardingViewModel.isPresented else {
            return
        }
        appState.dismissImagePreview()
    }
}
