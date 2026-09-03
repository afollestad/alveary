import Foundation

/// The text every scheduled run sends, built from its snapshot prompt.
extension DefaultScheduledTaskRunExecutor {
    /// Opens every scheduled run's outbound prompt, so the agent knows no one is at the keyboard.
    static let scheduledRunPreamble = "This is a scheduled task run."

    /// Applied in the executor, the single path from a run snapshot to a provider turn, rather
    /// than in the snapshot — so runs claimed before the preamble existed and recovered runs
    /// carry it too — and rather than in `ConversationViewModel`, so an injected
    /// `startAutomatedTurn` observes it and the view model stays a pass-through. It is both the
    /// transcript's user message and the transport text, and so also enters restore context,
    /// forks, and handoff summaries as true history.
    static func outboundPrompt(for prompt: String) -> String {
        "\(scheduledRunPreamble)\n\n\(prompt)"
    }
}
