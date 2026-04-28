import SwiftUI

struct ChatInputKeymapSheet: View {
    let supportsMidTurnSteering: Bool
    let defaultEnterBehavior: ThreadEnterDefaultBehavior

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
                    description: enterDescription
                )
                ChatInputKeymapRow(keys: "Shift + Enter", description: "Insert a newline.")

                if supportsMidTurnSteering {
                    ChatInputKeymapRow(
                        keys: "Command + Enter",
                        description: commandEnterDescription
                    )
                }

                ChatInputKeymapRow(
                    keys: "Esc, then Esc",
                    description: "During an active turn, double-tap escape to interrupt (stop) the turn."
                )
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 300, alignment: .topLeading)
    }

    init(
        supportsMidTurnSteering: Bool,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = AppSettings.defaultEnterBehavior
    ) {
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.defaultEnterBehavior = defaultEnterBehavior
    }

    private var enterDescription: String {
        guard supportsMidTurnSteering else {
            return "Send the message."
        }

        switch defaultEnterBehavior {
        case .queue:
            return "Send the message, or queue it while the agent is busy."
        case .steer:
            return "Send the message, or steer the current turn while the agent is busy."
        }
    }

    private var commandEnterDescription: String {
        switch defaultEnterBehavior {
        case .queue:
            return "Steer the current turn immediately while the agent is working."
        case .steer:
            return "Queue for the next turn while the agent is working."
        }
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
