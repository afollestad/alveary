import SwiftUI

struct DestructiveConfirmationRequest {
    let title: String
    let message: String
    let confirmTitle: String
    let confirm: () -> Void
}

extension View {
    func destructiveConfirmation(
        _ request: Binding<DestructiveConfirmationRequest?>
    ) -> some View {
        modifier(DestructiveConfirmationModifier(request: request))
    }
}

private struct DestructiveConfirmationModifier: ViewModifier {
    @Binding var request: DestructiveConfirmationRequest?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            request?.title ?? "",
            isPresented: Binding(
                get: { request != nil },
                set: { isPresented in
                    if !isPresented {
                        request = nil
                    }
                }
            ),
            presenting: request
        ) { confirmation in
            Button(confirmation.confirmTitle, role: .destructive) {
                let confirm = confirmation.confirm
                self.request = nil
                confirm()
            }

            Button("Cancel", role: .cancel) {
                self.request = nil
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}
