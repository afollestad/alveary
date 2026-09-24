import AgentCLIKit
import Foundation

/// Utility prompts require a read-only adapter; invalid inherited or saved choices stay visible until explicitly repaired.
extension SettingsViewModel {
    var utilityHarnessID: String { settingsService.current.effectiveUtilityHarness }
    var utilityUnavailableMessage: String? {
        guard HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: utilityHarnessID) else {
            return HarnessFeaturePolicy.unavailableUtilityMessage(harnessID: utilityHarnessID)
        }
        guard settingsService.current.isHarnessEnabled(utilityHarnessID) else {
            return "The selected harness is disabled. Enable it in Harnesses or select another harness."
        }
        if utilityHarnessID == "opencode" {
            guard let model = utilityOpenCodeModel else {
                return "Choose an available OpenCode model. Commit and pull request generation requires a concrete model."
            }
            if let variant = AppSettings.openCodeNativeEffort(stored: settingsService.current.effectiveUtilityEffort),
               !model.supportedEffortOptions.contains(where: { $0.value == variant }) {
                // Without variants the popover shows no effort slider; re-picking the checked model resets the effort.
                return model.supportedEffortOptions.isEmpty
                    ? "This model has no OpenCode efforts. Select it again to reset the saved effort."
                    : "Choose a supported OpenCode effort or Default for this model."
            }
        }
        return nil
    }

    /// Inherits the stored Threads default, which is what `AgentOneShotPromptService` launches when nothing is pinned.
    var utilityAgentPresentation: AgentReasoningPresentation {
        let settings = settingsService.current
        return AgentReasoningPresentation(
            harnesses: threadDefaultHarnessIDs
                .filter { HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: $0) }
                .map { utilityAgentHarness(for: $0) },
            pins: .init(harnessID: settings.utilityHarness, model: settings.utilityModel, effort: settings.utilityEffort),
            effective: .init(
                harness: utilityAgentHarness(for: utilityHarnessID),
                model: settings.effectiveUtilityModel,
                effort: settings.effectiveUtilityEffort
            ),
            inheritance: .init(
                title: "Threads default",
                target: .init(
                    harness: utilityAgentHarness(for: settings.defaultHarness),
                    model: settings.defaultModel,
                    effort: settings.effort
                ),
                isOffered: HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: settings.defaultHarness)
            ),
            isChecking: isCheckingThreadDefaultHarnesses
        )
    }

    func applyUtilityAgent(_ pins: AgentReasoningPins) -> Bool {
        settingsService.update {
            $0.utilityHarness = pins.harnessID
            $0.utilityModel = pins.model
            $0.utilityEffort = pins.effort
        }
        return true
    }

    /// OpenCode utility prompts need a concrete model, so its catalog drops the configured-default row.
    private func utilityAgentHarness(for harnessID: String) -> AgentReasoningPresentation.Harness {
        guard harnessID == "opencode" else {
            return agentReasoningHarness(for: harnessID)
        }
        return agentReasoningHarness(for: harnessID, concreteModelOptions: modelOptions(for: harnessID).filter { $0.model != nil })
    }

    private var utilityOpenCodeModel: AgentModelOption? {
        guard utilityHarnessID == "opencode" else { return nil }
        let selection = settingsService.current.effectiveUtilityModel
        return modelOptions(for: utilityHarnessID).first { $0.model != nil && ($0.id == selection || $0.model == selection) }
    }
}
