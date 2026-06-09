extension ConversationView {
    func applyComposerReasoningSpeedChange(_ speedMode: AgentSpeedMode) -> Bool {
        guard viewModel.canApplySettingsChange else {
            return false
        }
        guard composerCapabilities.supportsSpeedMode || speedMode == .standard else {
            viewModel.lastTurnError = "Fast mode is not supported by this provider."
            return false
        }
        let currentSpeedMode = conversation.thread?.normalizedSpeedMode ?? .standard
        guard currentSpeedMode != speedMode else {
            return true
        }
        _ = viewModel.applySpeedModeChange(speedMode, supportsSpeedMode: composerCapabilities.supportsSpeedMode)
        return (conversation.thread?.normalizedSpeedMode ?? .standard) == speedMode
    }
}
