import AgentCLIKit
import Foundation

extension ConversationViewModel {
    /// Restored rows can predate a persisted harness choice; their native binding still identifies the provider.
    var capabilityHarnessID: String {
        conversation.harness ?? conversation.harnessSessionHarnessId ?? settingsService.current.defaultHarness
    }

    var declaredHarnessFeatures: HarnessFeaturePolicy {
        .declared(harnessID: capabilityHarnessID)
    }

    func validateHarnessConfiguration(_ config: AgentSpawnConfig) async throws {
        try HarnessRequestValidation.validate(config)
        guard config.harnessId == "opencode" else { return }
        guard config.model != nil || config.effort != nil || !config.initialPromptAttachments.isEmpty else { return }
        let projectURL = URL(fileURLWithPath: config.workingDirectory, isDirectory: true)
        let status = await harnessDiscovery?.harnessStatuses(projectURL: projectURL)[.opencode]
        try HarnessRequestValidation.validateOpenCodeModel(
            model: config.model, effort: config.effort,
            hasImages: !config.initialPromptAttachments.isEmpty, status: status
        )
    }

    /// Runs before attachment consumption and again at delivery, since queued and restored messages can outlive model changes.
    func validateOutboundCapabilities(
        attachments: [LocalImageAttachment] = [], appShots: [AppShotAttachment] = [],
        initialGoal: String? = nil, usingLiveSettings: Bool = false
    ) async throws {
        let harnessID = capabilityHarnessID
        let policy = declaredHarnessFeatures
        if (initialGoal != nil || state.isGoalModeArmed) && !policy.supportsGoalMode {
            throw AgentError.spawnFailed("This harness does not support goals. Your goal has not been sent; choose a supported harness explicitly.")
        }
        guard harnessID == "opencode" else { return }
        let liveConfig = usingLiveSettings ? state.liveSessionConfig : nil
        let speed = liveConfig?.speedMode ?? dbThread()?.normalizedSpeedMode ?? .standard
        if speed == .fast {
            throw AgentError.spawnFailed("OpenCode does not support Fast mode. Select Standard before continuing.")
        }
        let selectedModel: String?
        let selectedEffort: String?
        if let liveConfig {
            selectedModel = liveConfig.model
            selectedEffort = liveConfig.effort
        } else {
            selectedModel = dbThread()?.model
            selectedEffort = AppSettings.openCodeNativeEffort(stored: dbThread()?.effort)
        }
        let hasImages = !attachments.isEmpty || !appShots.isEmpty
        guard selectedModel != nil || selectedEffort != nil || hasImages else { return }
        // A deleted worktree must reach the existing recovery path before probing its project configuration.
        if !usingLiveSettings { try repairMissingWorktreeIfNeeded() }
        let directory = liveConfig?.workingDirectory ?? dbThread()?.primaryWorkingDirectory
        let projectURL = directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let status = await harnessDiscovery?.harnessStatuses(projectURL: projectURL)[.opencode]
        try Task.checkCancellation()
        try HarnessRequestValidation.validateOpenCodeModel(
            model: selectedModel,
            effort: selectedEffort,
            hasImages: hasImages,
            status: status
        )
    }

    func validateStagedOptionalFeatures(supportsLocalImageInput: Bool, usingLiveSettings: Bool = false) async throws {
        if capabilityHarnessID == "opencode", !supportsLocalImageInput, !state.stagedImageAttachments.isEmpty {
            throw AgentError.spawnFailed("The selected OpenCode model cannot receive these images. Choose an image-capable model or remove them.")
        }
        try await validateOutboundCapabilities(
            attachments: state.stagedImageAttachments, appShots: state.stagedAppShots, usingLiveSettings: usingLiveSettings
        )
    }
}
