enum CommitMessageGenerationPromptDefaults {
    static let defaultPrompt = #"""
Generate a Git commit message for the provided changes.

Requirements:
- Use a concise subject line that describes the user-facing change.
- Include a body only when it adds useful context that is not obvious from the subject.
- Consider any existing project level or global level commit message guidelines.
- Wrap file names, class names, function names, variable names, or other code tokens with single ticks (`).
- When creating commits, use an appropriate trailer in the message.
    - If you are Claude: `Co-authored-by: Claude <noreply@anthropic.com>`
    - If you are Codex: `Co-authored-by: Codex <noreply@openai.com>`

Return only the commit message.
"""#
}
