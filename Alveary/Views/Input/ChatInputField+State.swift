import SwiftUI

extension ChatInputField {
    var presentation: ComposerPresentation {
        ComposerPresentation(
            text: text,
            mode: mode,
            defaultEnterBehavior: defaultEnterBehavior,
            supportsMidTurnSteering: supportsMidTurnSteering,
            isHandoffSteeringPromptActive: isHandoffSteeringPromptActive,
            isHandoffOutputPromptActive: isHandoffOutputPromptActive,
            handoffSteeringCountdown: handoffSteeringCountdown,
            sendCountdown: sendCountdown,
            isProjectTrustBlocked: isProjectTrustBlocked
        )
    }

    var trimmedText: String {
        presentation.trimmedText
    }

    var primaryActionTitle: String {
        presentation.primaryActionTitle
    }

    var primaryActionSystemImage: String {
        presentation.primaryActionSystemImage
    }

    var isPrimaryActionDisabled: Bool {
        presentation.isPrimaryActionDisabled
    }

    var isTextEditorDisabled: Bool {
        presentation.isTextEditorDisabled
    }

    var areControlsDisabled: Bool {
        presentation.areControlsDisabled
    }

    var canUseEscapeToStop: Bool {
        presentation.canUseEscapeToStop
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
        presentation.placeholder
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
