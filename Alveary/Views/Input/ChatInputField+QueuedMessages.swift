import SwiftUI

private let queuedMessagesBackgroundColor = Color.secondary.opacity(0.08)
private let queuedMessagesDividerColor = Color.primary.opacity(0.1)
private let queuedMessageIconColor = Color.gray
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
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: message.stagedContext == nil ? 0 : 5) {
                    HStack(alignment: .center, spacing: 12) {
                        queuedMessageIcon("clock")

                        VStack(alignment: .leading, spacing: message.stagedContext == nil ? 0 : 5) {
                            Group {
                                if containsMarkdownCode {
                                    // Queue items are composer chrome — render through the
                                    // `.composer` palette so their code chips match the live
                                    // input field's amber treatment rather than the neutral
                                    // gray used for historical/chrome surfaces.
                                    AppMarkdownText(
                                        markdown: message.text,
                                        inlineCodeStyle: .composer,
                                        taskStateScope: message.id.uuidString
                                    )
                                } else {
                                    Text(message.text)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if message.stagedContext != nil {
                                HStack(spacing: 6) {
                                    queuedMessageIcon("paperclip")

                                    Text("Context attached")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 10)

            if showsDivider {
                Rectangle()
                    .fill(queuedMessagesDividerColor)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func queuedMessageIcon(_ name: String) -> some View {
        if name == "clock" {
            QueuedMessageClockIcon()
                .stroke(
                    queuedMessageIconColor.opacity(0.75),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        } else {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(queuedMessageIconColor)
                .colorMultiply(queuedMessageIconColor)
                .opacity(0.75)
                .frame(width: 14)
                .accessibilityHidden(true)
        }
    }
}

/// Draws the legacy SwiftUI queue clock directly so snapshot/light appearances
/// cannot resolve the SF Symbol to a white fallback while the native AppKit path
/// is still being migrated in.
private struct QueuedMessageClockIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let bounds = CGRect(
            x: rect.midX - size / 2,
            y: rect.midY - size / 2,
            width: size,
            height: size
        ).insetBy(dx: 1, dy: 1)
        var path = Path()
        path.addEllipse(in: bounds)
        path.move(to: CGPoint(x: bounds.midX, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.28))
        path.move(to: CGPoint(x: bounds.midX, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.minX + bounds.width * 0.34, y: bounds.midY))
        return path
    }
}
