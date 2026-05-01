import Foundation

// Presentation types derive composer labels, disabled states, and submit/steer
// decisions from caller-owned state. They intentionally do not mutate drafts,
// persist settings, launch tasks, or talk to agent services.
enum ComposerPrimaryAction: Equatable, Sendable {
    case submit
    case steer
}

struct ComposerPresentation: Equatable, Sendable {
    static let handoffSteeringPlaceholder = "Add steering for the session handoff, or submit empty to continue..."

    let text: String
    let mode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let supportsMidTurnSteering: Bool
    let isHandoffSteeringPromptActive: Bool
    let isHandoffOutputPromptActive: Bool
    let handoffSteeringCountdown: Int?
    let sendCountdown: Int?
    let isProjectTrustBlocked: Bool

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

        if let sendCountdown {
            return "Submit (\(sendCountdown))"
        }

        if isHandoffOutputPromptActive {
            return "Submit"
        }

        return "Send"
    }

    var primaryActionSystemImage: String {
        (isHandoffSteeringPromptActive || isHandoffOutputPromptActive || sendCountdown != nil) ? "checkmark" : "paperplane.fill"
    }

    var isPrimaryActionDisabled: Bool {
        if isProjectTrustBlocked {
            return true
        }
        return !isHandoffSteeringPromptActive && trimmedText.isEmpty
    }

    var isTextEditorDisabled: Bool {
        if isProjectTrustBlocked {
            return true
        }
        if case .progressOnly = mode {
            return true
        }
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

    var placeholder: String {
        if isProjectTrustBlocked {
            return "Trust this project to enable the composer"
        }

        switch mode {
        case .idle:
            if isHandoffSteeringPromptActive {
                return Self.handoffSteeringPlaceholder
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

    var canSubmit: Bool {
        !isProjectTrustBlocked && (isHandoffSteeringPromptActive || !trimmedText.isEmpty)
    }

    var canSteer: Bool {
        !isProjectTrustBlocked && !trimmedText.isEmpty
    }

    func busyReturnAction(usesAlternateBehavior: Bool) -> ComposerPrimaryAction {
        guard case .busy(let canStop) = mode,
              canStop,
              supportsMidTurnSteering else {
            return .submit
        }

        switch (defaultEnterBehavior, usesAlternateBehavior) {
        case (.queue, false), (.steer, true):
            return .submit
        case (.steer, false), (.queue, true):
            return .steer
        }
    }
}

enum ComposerSettingsPresentation {
    static func visibleEffortLevels(
        selectedModel: String,
        providerSupportedEffortLevels: [String]
    ) -> [String] {
        let modelSupported = Set(AppSettings.supportedEffortLevels(forModel: selectedModel))
        return providerSupportedEffortLevels.filter(modelSupported.contains)
    }
}
