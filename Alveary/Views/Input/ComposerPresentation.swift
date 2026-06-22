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
    static let goalPlaceholder = "Provide a goal..."

    let text: String
    private let textIsEffectivelyEmpty: Bool
    let mode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let supportsMidTurnSteering: Bool
    let canSteerCurrentTurn: Bool
    let isHandoffSteeringPromptActive: Bool
    let isHandoffOutputPromptActive: Bool
    let handoffSteeringCountdown: Int?
    let sendCountdown: Int?
    let isProjectTrustBlocked: Bool
    let isGoalModeArmed: Bool

    init(
        text: String,
        isTextEffectivelyEmpty: Bool? = nil,
        mode: ComposerMode,
        defaultEnterBehavior: ThreadEnterDefaultBehavior,
        supportsMidTurnSteering: Bool,
        canSteerCurrentTurn: Bool = true,
        isHandoffSteeringPromptActive: Bool,
        isHandoffOutputPromptActive: Bool,
        handoffSteeringCountdown: Int?,
        sendCountdown: Int?,
        isProjectTrustBlocked: Bool,
        isGoalModeArmed: Bool = false
    ) {
        self.text = text
        textIsEffectivelyEmpty = isTextEffectivelyEmpty ?? ChatComposerTextSupport.isEffectivelyEmpty(text)
        self.mode = mode
        self.defaultEnterBehavior = defaultEnterBehavior
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.canSteerCurrentTurn = canSteerCurrentTurn
        self.isHandoffSteeringPromptActive = isHandoffSteeringPromptActive
        self.isHandoffOutputPromptActive = isHandoffOutputPromptActive
        self.handoffSteeringCountdown = handoffSteeringCountdown
        self.sendCountdown = sendCountdown
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.isGoalModeArmed = isGoalModeArmed
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isTextEffectivelyEmpty: Bool {
        textIsEffectivelyEmpty
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
        return !isHandoffSteeringPromptActive && isTextEffectivelyEmpty
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
        case .busy(let canStop):
            return !canStop
        case .progressOnly(.toolApproval):
            return false
        case .progressOnly:
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
            if isGoalModeArmed {
                return Self.goalPlaceholder
            }
            return "Ask anything, @ to add files, / for skills"
        case .busy(let canStop):
            if canStop, supportsMidTurnSteering, canSteerCurrentTurn {
                switch defaultEnterBehavior {
                case .queue:
                    return "Enter to queue for the next turn, or Cmd+Enter to steer..."
                case .steer:
                    return "Enter to steer the current turn, or Cmd+Enter to queue..."
                }
            }
            return "Type a message to queue for the next turn..."
        case .progressOnly(let reason):
            return ChatComposerTextSupport.placeholder(for: reason)
        }
    }

    var canSubmit: Bool {
        !isProjectTrustBlocked && (isHandoffSteeringPromptActive || !isTextEffectivelyEmpty)
    }

    var canSteer: Bool {
        !isProjectTrustBlocked && !isTextEffectivelyEmpty && canSteerCurrentTurn
    }

    func busyReturnAction(usesAlternateBehavior: Bool) -> ComposerPrimaryAction {
        guard case .busy(let canStop) = mode,
              canStop,
              supportsMidTurnSteering,
              canSteerCurrentTurn else {
            return .submit
        }

        switch (defaultEnterBehavior, usesAlternateBehavior) {
        case (.queue, false), (.steer, true):
            return .submit
        case (.steer, false), (.queue, true):
            return .steer
        }
    }

    func canUseAlternateSteer(usesAlternateBehavior: Bool) -> Bool {
        // The live draft is only authoritative after `ChatView` flushes the editor,
        // so text emptiness is intentionally not part of this routing gate.
        !isProjectTrustBlocked &&
            defaultEnterBehavior == .queue &&
            usesAlternateBehavior &&
            busyReturnAction(usesAlternateBehavior: usesAlternateBehavior) == .steer
    }
}
