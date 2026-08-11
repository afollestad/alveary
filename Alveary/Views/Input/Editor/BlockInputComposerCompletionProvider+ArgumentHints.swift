import BlockInputKit
import Foundation

extension BlockInputComposerCompletionProvider {
    /// Local hints are rebuilt from the current availability on every keystroke, so `/effort` and `/model` stay live
    /// across model and provider refreshes without replacing the completion provider.
    static func argumentHints(
        localCommands: ComposerLocalCommandAvailability,
        passthroughCommands: [ComposerPassthroughSlashCommand],
        skillHints: [(command: String, hint: String)]
    ) -> BlockInputSlashCommandArgumentHints {
        var localHints: [(command: String, hint: String)] = []
        if localCommands.supportsSessionHandoff {
            localHints.append((command: ComposerLocalCommandKind.handoff.command, hint: "Optional steering prompt"))
        }
        if localCommands.isEnabled(.effort) {
            localHints.append((
                command: ComposerLocalCommandKind.effort.command,
                hint: localCommands.supportedEffortOptions.joined(separator: "|")
            ))
        }
        if localCommands.isEnabled(.model) {
            localHints.append((
                command: ComposerLocalCommandKind.model.command,
                hint: localCommands.modelArgumentHint
            ))
        }
        let passthroughHints = passthroughCommands.compactMap { command -> (command: String, hint: String)? in
            guard let hint = command.argumentHint?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hint.isEmpty else {
                return nil
            }
            return (command: command.command, hint: hint)
        }
        return BlockInputSlashCommandArgumentHints(commandHints: localHints + passthroughHints + skillHints)
    }

    static func skillArgumentHints(skills: [Skill]) -> [(command: String, hint: String)] {
        skills.flatMap { skill in
            guard let argumentHint = skill.argumentHint?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !argumentHint.isEmpty else {
                return [(command: String, hint: String)]()
            }
            return [
                (command: skill.name, hint: argumentHint),
                (command: skill.id, hint: argumentHint)
            ]
        }
    }
}
