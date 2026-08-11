import AgentCLIKit
import AppKit

extension AgentGoalStatus {
    var composerTitle: String {
        switch self {
        case .active:
            return "Pursuing goal"
        case .paused:
            return "Goal paused"
        case .achieved:
            return "Goal achieved"
        case .blocked, .usageLimited:
            return "Goal stopped"
        case .cleared:
            return "Goal cleared"
        }
    }

    var goalAccentColor: NSColor {
        switch self {
        case .active:
            return .systemBlue
        case .paused:
            return .secondaryLabelColor
        case .achieved:
            return .systemGreen
        case .blocked, .usageLimited:
            return .systemOrange
        case .cleared:
            return .secondaryLabelColor
        }
    }

    var isComposerRestartableTerminal: Bool {
        switch self {
        case .blocked, .usageLimited:
            return true
        case .active, .paused, .achieved, .cleared:
            return false
        }
    }
}

extension AppKitChatComposerTopContentSeverity {
    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        case .info:
            return .systemBlue
        }
    }
}
