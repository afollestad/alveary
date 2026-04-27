import SwiftUI

struct ChatInputSendFootprintLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            ChatInputActionLabel("Send", systemImage: "paperplane.fill")
                .hidden()
            content()
        }
    }
}

struct ChatInputSendFootprintSlot<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(
            action: {},
            label: {
                ChatInputSendFootprintLabel {
                    EmptyView()
                }
            }
        )
        .primaryActionButtonStyle()
        .disabled(true)
        .accessibilityHidden(true)
        .overlay {
            content()
        }
    }
}
