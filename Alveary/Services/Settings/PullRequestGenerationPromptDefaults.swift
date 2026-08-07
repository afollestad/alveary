enum PullRequestGenerationPromptDefaults {
    static let defaultPrompt = #"""
Generate a pull request title and description for the provided branch commits.

Requirements:

- The first line of your response is the pull request title: concise and user-facing, with no trailing period.
- Leave one blank line after the title; everything after it is the description body.
- Write the description as GitHub-flavored markdown summarizing what changed and why.
- Consider any existing project level or global level pull request guidelines.
- Wrap file names, class names, function names, variable names, or other code tokens with single ticks (`).

Return only the title and description.
"""#
}
