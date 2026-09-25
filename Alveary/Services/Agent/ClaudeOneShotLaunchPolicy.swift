import Foundation

/// Environment for Claude `-p` one-shot prompts: collective review workers and commit and pull request generation.
enum ClaudeOneShotLaunchPolicy {
    /// A gateway URL set only in Claude's remote settings never reaches these launch environments, so Claude sends
    /// experimental request fields that the gateway rejects on the first request after a tool call.
    static func environment(
        harnessID: String,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        guard harnessID == "claude" else {
            return baseEnvironment
        }
        var environment = baseEnvironment
        environment["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] = "1"
        return environment
    }
}
