@preconcurrency import AppKit
import Foundation
import SwiftUI

extension ChatView {
    var pausedQueueSendModal: AppWindowModalOverlayPresenter.Modal? {
        guard let confirmation = viewModel.state.pausedQueueSendConfirmation,
              viewModel.state.queuedMessagesPauseReason != nil,
              !viewModel.messageQueue.pending.isEmpty else {
            return nil
        }

        return AppWindowModalOverlayPresenter.Modal(
            id: "paused-queue-send-\(confirmation.id)-\(confirmation.isResolving)",
            content: AnyView(
                PausedQueueSendConfirmationModal(
                    messageText: confirmation.messageText,
                    isResolving: confirmation.isResolving,
                    onDismiss: {
                        dismissPausedQueueSendConfirmation()
                    },
                    onClearQueue: {
                        clearPausedQueueFromSendConfirmation()
                    },
                    onSendMessage: {
                        sendPausedQueueConfirmedDraft()
                    }
                )
            )
        )
    }

    @discardableResult
    func presentPausedQueueSendConfirmationIfNeeded(draft: ComposerDraft) -> Bool {
        guard shouldPresentPausedQueueSendConfirmation else {
            return false
        }

        viewModel.state.pausedQueueSendConfirmation = PausedQueueSendConfirmationState(
            draft: draft,
            queuedMessageCount: viewModel.messageQueue.pending.count
        )
        return true
    }

    func dismissPausedQueueSendConfirmation() {
        viewModel.state.pausedQueueSendConfirmation = nil
        appState.requestComposerFocus()
    }

    func clearPausedQueueFromSendConfirmation() {
        guard let confirmation = viewModel.state.pausedQueueSendConfirmation else {
            return
        }

        viewModel.state.pausedQueueSendConfirmation?.isResolving = true
        let draft = confirmation.draft
        viewModel.clearPausedQueuedMessages()
        viewModel.state.pausedQueueSendConfirmation = nil
        requestScrollToBottom()
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        sendSubmittedDraft(draft, isSessionHandoffDraft: false)
    }

    func sendPausedQueueConfirmedDraft() {
        guard let confirmation = viewModel.state.pausedQueueSendConfirmation else {
            return
        }

        viewModel.state.pausedQueueSendConfirmation?.isResolving = true
        let draft = confirmation.draft
        viewModel.state.pausedQueueSendConfirmation = nil
        requestScrollToBottom()
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        sendSubmittedDraft(draft, isSessionHandoffDraft: false, sendBeforePausedQueue: true)
    }

    private var shouldPresentPausedQueueSendConfirmation: Bool {
        viewModel.state.queuedMessagesPauseReason != nil &&
            viewModel.messageQueue.peekNext() != nil &&
            !isSessionHandoffOutputSendActive
    }

    private var isSessionHandoffOutputSendActive: Bool {
        viewModel.state.handoffCountdownRemaining != nil ||
            viewModel.state.pendingHandoffOutput != nil
    }
}

struct PausedQueueSendConfirmationModal: View {
    let messageText: String
    let isResolving: Bool
    let onDismiss: () -> Void
    let onClearQueue: () -> Void
    let onSendMessage: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.44)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isResolving else {
                            return
                        }
                        onDismiss()
                    }

                panel(width: panelWidth(availableWidth: proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .zIndex(1000)
    }

    private func panel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            message
            actions
        }
        .padding(.top, 24)
        .padding(.leading, 32)
        .padding(.bottom, 28)
        .padding(.trailing, 32)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.36), radius: 28, x: 0, y: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Send message confirmation")
    }

    private func panelWidth(availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth - 80, 340), 620)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("Send message?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 16)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PausedQueueModalCloseButtonStyle())
            .disabled(isResolving)
            .accessibilityLabel("Close send message confirmation")
        }
    }

    private var message: some View {
        Text(messageText)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            Button(action: onClearQueue) {
                Text("Clear queue")
            }
            .buttonStyle(PausedQueueModalDestructiveButtonStyle())
            .disabled(isResolving)
            .accessibilityHint("Clears the paused queued messages and sends the current draft.")

            Button(action: onSendMessage) {
                Text(isResolving ? "Sending..." : "Send message")
            }
            .buttonStyle(PausedQueueModalPrimaryButtonStyle())
            .disabled(isResolving)
            .accessibilityHint("Sends the current draft and resumes the paused queue afterward.")
        }
        .padding(.top, 22)
    }
}

private struct PausedQueueModalCloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PausedQueueModalCloseButtonBody(configuration: configuration)
    }
}

private struct PausedQueueModalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PausedQueueModalActionButtonBody(
            configuration: configuration,
            foregroundColor: .primary,
            fillColor: AppAccentFill.primary,
            pressedFillColor: AppAccentFill.pressed,
            focusedFillColor: AppAccentFill.primary,
            minWidth: 138
        )
    }
}

private struct PausedQueueModalDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PausedQueueModalActionButtonBody(
            configuration: configuration,
            foregroundColor: Color.red.opacity(configuration.isPressed ? 0.86 : 0.96),
            fillColor: Color.red.opacity(0.12),
            pressedFillColor: Color.red.opacity(0.20),
            focusedFillColor: Color.red.opacity(0.16),
            minWidth: 132
        )
    }
}

private struct PausedQueueModalCloseButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(Color.secondary.opacity(isEnabled ? 1 : 0.45))
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .overlay(
                Circle()
                    .stroke(focusStrokeColor, lineWidth: 1.5)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && isEnabled ? 0.94 : 1)
            .focusEffectDisabled()
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return .clear
        }
        if configuration.isPressed {
            return Color.primary.opacity(0.14)
        }
        return isFocused ? Color.primary.opacity(0.08) : .clear
    }

    private var focusStrokeColor: Color {
        guard isEnabled, isFocused else {
            return .clear
        }
        return AppAccentFill.primary.opacity(0.72)
    }
}

private struct PausedQueueModalActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let foregroundColor: Color
    let fillColor: Color
    let pressedFillColor: Color
    let focusedFillColor: Color
    let minWidth: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor.opacity(isEnabled ? 1 : 0.5))
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(minWidth: minWidth, minHeight: 36)
            .background(
                buttonShape
                    .fill(backgroundColor)
            )
            .overlay(
                buttonShape
                    .stroke(focusStrokeColor, lineWidth: 1.5)
            )
            .contentShape(buttonShape)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .focusEffectDisabled()
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return fillColor.opacity(0.38)
        }
        if configuration.isPressed {
            return pressedFillColor
        }
        return isFocused ? focusedFillColor : fillColor
    }

    private var focusStrokeColor: Color {
        guard isEnabled, isFocused else {
            return .clear
        }
        return AppAccentFill.primary.opacity(0.72)
    }
}

private extension PausedQueueSendConfirmationState {
    var messageText: String {
        let noun = queuedMessageCount == 1 ? "message" : "messages"
        return "You are about to send a message. Do you want to clear the \(queuedMessageCount) \(noun) previously queued?"
    }
}
