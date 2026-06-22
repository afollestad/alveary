import Foundation

enum ComposerLocalCommandKind: String, CaseIterable, Sendable, Equatable {
    case goal
    case plan
    case fast
    case handoff

    var command: String { rawValue }
    var displayName: String { "/\(rawValue)" }
}

struct ComposerLocalCommand: Sendable, Equatable {
    let kind: ComposerLocalCommandKind
    let argument: String
}

struct ComposerLocalCommandAvailability: Sendable, Equatable {
    var supportsGoalMode = false
    var supportsPlanMode = false
    var supportsSpeedMode = false
    var supportsSessionHandoff = false
    var suppressesSlashCommandSuggestions = false

    var enabledKinds: [ComposerLocalCommandKind] {
        ComposerLocalCommandKind.allCases.filter(isEnabled)
    }

    var reservedKinds: [ComposerLocalCommandKind] {
        ComposerLocalCommandKind.allCases.filter(isReserved)
    }

    func isEnabled(_ kind: ComposerLocalCommandKind) -> Bool {
        switch kind {
        case .goal:
            supportsGoalMode
        case .plan:
            supportsPlanMode
        case .fast:
            supportsSpeedMode
        case .handoff:
            supportsSessionHandoff
        }
    }

    func isReserved(_ kind: ComposerLocalCommandKind) -> Bool {
        kind == .goal || isEnabled(kind)
    }
}

/// Suggested locally but submitted as raw provider text, not intercepted by `ComposerLocalCommandParser`.
struct ComposerPassthroughSlashCommand: Sendable, Equatable {
    let command: String
    let subtitle: String
    let detailText: String
    let uri: String
    let argumentHint: String?

    var displayName: String { "/\(command)" }
}

enum ComposerLocalCommandParser {
    static func parse(_ text: String, availability: ComposerLocalCommandAvailability) -> ComposerLocalCommand? {
        guard text.hasPrefix("/") else {
            return nil
        }

        let commandAndArgument = text.dropFirst()
        let commandEnd = commandAndArgument.firstIndex(where: \.isWhitespace) ?? commandAndArgument.endIndex
        let command = String(commandAndArgument[..<commandEnd]).lowercased()
        guard let kind = ComposerLocalCommandKind(rawValue: command),
              availability.isReserved(kind) else {
            return nil
        }

        let argument = String(commandAndArgument[commandEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ComposerLocalCommand(kind: kind, argument: argument)
    }
}
