import SwiftUI

extension ChatInputField {
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var primaryActionTitle: String {
        if isHandoffSteeringPromptActive {
            guard let handoffSteeringCountdown else {
                return "Submit"
            }
            return "Submit (\(handoffSteeringCountdown))"
        }

        guard let sendCountdown else {
            return "Send"
        }
        return "Send (\(sendCountdown))"
    }

    var primaryActionSystemImage: String {
        isHandoffSteeringPromptActive ? "checkmark" : "paperplane.fill"
    }

    var isPrimaryActionDisabled: Bool {
        if isProjectTrustBlocked {
            return true
        }
        return !isHandoffSteeringPromptActive && trimmedText.isEmpty
    }

    var isTextEditorDisabled: Bool {
        if isProjectTrustBlocked { return true }
        if case .progressOnly = mode { return true }
        return false
    }

    var areControlsDisabled: Bool {
        if isProjectTrustBlocked {
            return true
        }

        switch mode {
        case .idle:
            return isHandoffSteeringPromptActive
        case .busy, .progressOnly:
            return true
        }
    }

    var canUseEscapeToStop: Bool {
        switch mode {
        case .busy(let canStop): return canStop
        case .progressOnly(let reason): return reason.canStop
        case .idle: return false
        }
    }

    var modelOptions: [String] {
        knownModels.contains(selectedModel) ? knownModels : knownModels + [selectedModel]
    }

    var inputBorderColor: Color {
        isDropTargeted ? .accentColor : Color.secondary.opacity(0.18)
    }

    var inputBorderWidth: CGFloat {
        isDropTargeted ? 1.5 : 1
    }

    var placeholder: String {
        if isProjectTrustBlocked {
            return "Trust this project to enable the composer"
        }

        switch mode {
        case .idle:
            if isHandoffSteeringPromptActive {
                return ConversationViewModel.handoffSteeringPlaceholder
            }
            return "Ask anything, @ to add files, / for skills"
        case .busy(let canStop):
            if canStop, supportsMidTurnSteering {
                switch defaultEnterBehavior {
                case .queue:
                    return "Enter to queue for the next turn, or Cmd+Enter to steer..."
                case .steer:
                    return "Enter to steer the current turn, or Cmd+Enter to queue..."
                }
            }
            return "Type a message to queue for the next turn..."
        case .progressOnly(let reason):
            return ChatInputFieldTextSupport.placeholder(for: reason)
        }
    }

    var inlineSlashCommandHint: AppTextEditorInlineHint? {
        guard let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: textSelection,
            isInputFocused: isComposerFirstResponder,
            commandHints: skillArgumentHints
        ) else {
            return nil
        }

        return AppTextEditorInlineHint(text: hint)
    }
}
