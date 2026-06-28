import SwiftUI

struct AppImagePreviewWindowPresenter: View {
    let request: AppImagePreviewRequest?
    let onDismiss: () -> Void

    var body: some View {
        AppWindowModalOverlayPresenter(
            modal: request.map { request in
                AppWindowModalOverlayPresenter.Modal(
                    id: "image-preview-\(request.id)",
                    content: AnyView(
                        AppImagePreviewOverlay(
                            request: request,
                            onDismiss: onDismiss
                        )
                    )
                )
            },
            onDismiss: onDismiss
        )
    }
}
