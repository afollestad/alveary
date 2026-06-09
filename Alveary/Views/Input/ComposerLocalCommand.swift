import Foundation

enum ComposerLocalCommandKind: String, CaseIterable, Sendable, Equatable {
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
    var supportsPlanMode = false
    var supportsSpeedMode = false
    var supportsSessionHandoff = false

    var enabledKinds: [ComposerLocalCommandKind] {
        ComposerLocalCommandKind.allCases.filter(isEnabled)
    }

    func isEnabled(_ kind: ComposerLocalCommandKind) -> Bool {
        switch kind {
        case .plan:
            supportsPlanMode
        case .fast:
            supportsSpeedMode
        case .handoff:
            supportsSessionHandoff
        }
    }
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
              availability.isEnabled(kind) else {
            return nil
        }

        let argument = String(commandAndArgument[commandEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ComposerLocalCommand(kind: kind, argument: argument)
    }
}
