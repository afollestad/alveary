import SwiftUI

struct ChatInputStopButton: View {
    let isConfirmationArmed: Bool
    let action: () -> Void

    private var title: String {
        isConfirmationArmed ? "Confirm" : "Stop"
    }

    var body: some View {
        Button(action: action) {
            ChatInputActionLabel(title, systemImage: "stop.fill")
                .fixedSize(horizontal: true, vertical: false)
        }
        .destructiveActionButtonStyle()
        .accessibilityLabel(isConfirmationArmed ? "Confirm stop" : "Stop")
        .animation(.easeInOut(duration: 0.18), value: isConfirmationArmed)
    }
}
