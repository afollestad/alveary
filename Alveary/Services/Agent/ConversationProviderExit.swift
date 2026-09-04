import AgentCLIKit

/// Transcript note for a provider process that ended when Alveary did not end it. Host teardown stops
/// accepting live events before destroying the process, so an `.exited` lifecycle with an exit code
/// only reaches the transcript when the exit was unexpected.
enum ConversationProviderExit {
    static func displayMessage(providerId: AgentProviderID, exitCode: Int32) -> String {
        "\(providerName(for: providerId)) exited unexpectedly (exit code \(exitCode))"
    }

    static func failureMessage(providerId: AgentProviderID, exitCode: Int32) -> String {
        "\(providerName(for: providerId)) failed (exit code \(exitCode))"
    }

    static func isDisplayMessage(_ text: String?) -> Bool {
        text?.contains(" exited unexpectedly (exit code ") == true
    }

    private static func providerName(for providerId: AgentProviderID) -> String {
        switch providerId {
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }
}
