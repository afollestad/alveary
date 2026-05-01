import Foundation

enum SessionHandoffPromptBuilder {
    static func hiddenPrompt(
        configuredPrompt: String,
        steeringPrompt: String?,
        isSteeringEnabled: Bool
    ) -> String {
        guard isSteeringEnabled,
              let steeringPrompt,
              !steeringPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return configuredPrompt
        }

        return configuredPrompt + #"""

## User Handoff Steering

The user provided the following steering prompt for this session handoff. Treat it
as the primary relevance filter for the handoff you produce. Preserve the base
handoff behavior above, but focus the output on what the user asks for here.

User steering prompt:
"""# + "\n" + steeringPrompt
    }

    static func outgoingMessage(
        handoffOutput: String,
        steeringPrompt: String?,
        isSteeringEnabled: Bool
    ) -> String {
        let handoffOutput = editableHandoffOutput(handoffOutput)
        guard isSteeringEnabled,
              let steeringPrompt,
              !steeringPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return handoffOutput
        }

        return handoffOutput + "\n\n## User Prompt\n" + steeringPrompt
    }

    static func editableHandoffOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        var lines = trimmed.components(separatedBy: .newlines)
        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```"),
              let lastLine = lines.last,
              lastLine.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
            return trimmed
        }

        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
