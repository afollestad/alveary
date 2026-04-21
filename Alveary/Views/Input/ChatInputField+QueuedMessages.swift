import SwiftUI

private let queuedMessagesBackgroundColor = Color.secondary.opacity(0.08)
private let queuedMessagesDividerColor = Color.primary.opacity(0.1)
private let queuedMessageActionsWidth: CGFloat = 176

struct ChatInputQueuedMessagesSection: View {
    let queuedMessages: [QueuedMessage]
    let supportsMidTurnSteering: Bool
    let isTurnActive: Bool
    let inFlightQueuedMessageID: UUID?
    let borderColor: Color
    let borderWidth: CGFloat
    let onSteerQueuedMessage: (UUID) -> Void
    let onEditQueuedMessage: (UUID) -> Void
    let onDismissQueuedMessage: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(queuedMessages.enumerated()), id: \.element.id) { index, message in
                ChatInputQueuedMessageRow(
                    message: message,
                    showsDivider: index < queuedMessages.count - 1,
                    isSteerDisabled: !supportsMidTurnSteering || !isTurnActive || inFlightQueuedMessageID != nil,
                    areRowActionsDisabled: inFlightQueuedMessageID != nil,
                    onSteer: {
                        onSteerQueuedMessage(message.id)
                    },
                    onEdit: {
                        onEditQueuedMessage(message.id)
                    },
                    onDismiss: {
                        onDismissQueuedMessage(message.id)
                    }
                )
            }
        }
        .background(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 18,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 18
                ),
                style: .continuous
            )
            .fill(queuedMessagesBackgroundColor)
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 18,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 18
                ),
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 18,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 18
                ),
                style: .continuous
            )
            .stroke(borderColor, lineWidth: borderWidth)
        )
    }
}

private struct ChatInputQueuedMessageRow: View {
    let message: QueuedMessage
    let showsDivider: Bool
    let isSteerDisabled: Bool
    let areRowActionsDisabled: Bool
    let onSteer: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    private var containsMarkdownCode: Bool {
        AppMarkdownCodeBlockParser.containsCode(in: message.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: message.stagedContext == nil ? 0 : 5) {
                    Group {
                        if containsMarkdownCode {
                            // Queue items are composer chrome — render through the
                            // `.composer` palette so their code chips match the live
                            // input field's amber treatment rather than the neutral
                            // gray used for historical/chrome surfaces.
                            AppMarkdownText(markdown: message.text, inlineCodeStyle: .composer)
                        } else {
                            Text(message.text)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if message.stagedContext != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                                .font(.caption.weight(.semibold))
                                .accessibilityHidden(true)

                            Text("Context attached")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Button(action: onSteer) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.left")
                            Text("Steer")
                        }
                    }
                    .controlSize(.regular)
                    .secondaryActionButtonStyle()
                    .disabled(isSteerDisabled)

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .iconActionButtonStyle()
                    .accessibilityLabel("Edit queued message")
                    .help("Edit queued message")
                    .disabled(areRowActionsDisabled)

                    Button(action: onDismiss) {
                        Image(systemName: "trash")
                    }
                    .destructiveIconActionButtonStyle()
                    .accessibilityLabel("Discard queued message")
                    .help("Discard queued message")
                    .disabled(areRowActionsDisabled)
                }
                .frame(width: queuedMessageActionsWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if showsDivider {
                Rectangle()
                    .fill(queuedMessagesDividerColor)
                    .frame(height: 1)
            }
        }
    }
}
