import Foundation

enum CommitMessageGenerationPromptBuilder {
    static func build(
        editablePrompt: String,
        includeUnstagedChanges: Bool,
        context: String
    ) -> String {
        [
            prefix(includeUnstagedChanges: includeUnstagedChanges),
            editablePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            context.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    static func prefix(includeUnstagedChanges: Bool) -> String {
        if includeUnstagedChanges {
            return "You are generating a commit message for **UNSTAGED** changes."
        }
        return "You are generating a commit message for **STAGED** changes."
    }
}
