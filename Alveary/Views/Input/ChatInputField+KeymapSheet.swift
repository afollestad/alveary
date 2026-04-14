import SwiftUI

struct ChatInputKeymapSheet: View {
    let supportsMidTurnSteering: Bool

    @Environment(\.dismiss) private var dismiss

    private let description = "Use these shortcuts while typing in the chat composer."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsScreenHeader(
                title: "Keyboard shortcuts",
                description: description,
                onClose: dismiss.callAsFunction
            )

            VStack(spacing: 12) {
                ChatInputKeymapRow(
                    keys: "Enter",
                    description: supportsMidTurnSteering
                        ? "Send the message, or queue it while the agent is busy."
                        : "Send the message."
                )
                ChatInputKeymapRow(keys: "Shift + Enter", description: "Insert a newline.")

                if supportsMidTurnSteering {
                    ChatInputKeymapRow(
                        keys: "Option + Enter",
                        description: "Steer the current turn immediately while the agent is working."
                    )
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220, alignment: .topLeading)
    }
}

private struct ChatInputKeymapRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(keys)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)

            Text(description)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
