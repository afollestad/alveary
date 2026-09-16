import AgentCLIKit

/// Transcript note for a harness process that ended when Alveary did not end it. Host teardown stops
/// accepting live events before destroying the process, so an `.exited` lifecycle with an exit code
/// only reaches the transcript when the exit was unexpected.
enum ConversationHarnessExit {
    static func displayMessage(harnessId: AgentHarnessID, exitCode: Int32) -> String {
        "\(harnessName(for: harnessId)) exited unexpectedly (exit code \(exitCode))"
    }

    static func failureMessage(harnessId: AgentHarnessID, exitCode: Int32) -> String {
        "\(harnessName(for: harnessId)) failed (exit code \(exitCode))"
    }

    static func isDisplayMessage(_ text: String?) -> Bool {
        text?.contains(" exited unexpectedly (exit code ") == true
    }

    private static func harnessName(for harnessId: AgentHarnessID) -> String {
        switch harnessId {
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        }
    }
}
