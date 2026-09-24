import AgentCLIKit
import Foundation

/// Utility prompts require a read-only adapter; invalid inherited or saved choices stay visible until explicitly repaired.
extension SettingsViewModel {
    var utilityHarnessSelection: String { settingsService.current.utilityHarness ?? Self.pullRequestReviewInheritValue }
    var utilityHarnessOptions: [String] {
        let inherited = HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: settingsService.current.defaultHarness)
            ? [Self.pullRequestReviewInheritValue] : []
        var values = inherited + threadDefaultHarnessIDs.filter {
            HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: $0)
        }
        if let selected = settingsService.current.utilityHarness,
           HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: selected), !values.contains(selected) { values.append(selected) }
        return values
    }
    var utilityHarnessID: String { settingsService.current.effectiveUtilityHarness }
    var canConfigureUtilityModel: Bool {
        HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: utilityHarnessID)
            && settingsService.current.isHarnessEnabled(utilityHarnessID)
    }
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
                return "Choose a supported OpenCode effort or Default for this model."
            }
        }
        return nil
    }
    var utilityModelSelection: String { settingsService.current.utilityModel ?? Self.pullRequestReviewInheritValue }
    var utilityModelOptions: [String] {
        if utilityHarnessID == "opencode" {
            var values = [Self.pullRequestReviewInheritValue] + modelOptions(for: utilityHarnessID).filter { $0.model != nil }.map(\.id)
            if let selected = settingsService.current.utilityModel, !values.contains(selected) { values.append(selected) }
            return values
        }
        return [Self.pullRequestReviewInheritValue] + modelOptionValues(for: utilityHarnessID, including: settingsService.current.utilityModel)
    }
    var utilityEffortSelection: String {
        guard let stored = settingsService.current.utilityEffort else { return Self.pullRequestReviewInheritValue }
        return utilityHarnessID == "opencode" ? AppSettings.openCodePickerEffort(stored: stored) : stored
    }
    var utilityEffortOptions: [String] {
        guard canConfigureUtilityModel else { return [] }
        var values = utilityModelEffortOptions.map(\.value)
        guard !values.isEmpty else { return [] }
        if settingsService.current.utilityEffort != nil, !values.contains(utilityEffortSelection) { values.append(utilityEffortSelection) }
        return [Self.pullRequestReviewInheritValue] + values
    }

    func setUtilityHarness(_ value: String) {
        settingsService.update {
            $0.utilityHarness = value == Self.pullRequestReviewInheritValue ? nil : value
            $0.utilityModel = nil
            $0.utilityEffort = nil
        }
    }
    func setUtilityModel(_ value: String) {
        let options = modelOptions(for: utilityHarnessID)
        let usesNativeVariants = utilityHarnessID == "opencode"
        settingsService.update {
            $0.utilityModel = value == Self.pullRequestReviewInheritValue ? nil
                : AgentModelOptionSelection.storedModelValue(in: options, matching: value)
            $0.utilityEffort = usesNativeVariants && value != Self.pullRequestReviewInheritValue ? AppSettings.openCodeDefaultEffort : nil
        }
    }
    func setUtilityEffort(_ value: String) {
        settingsService.update { $0.utilityEffort = value == Self.pullRequestReviewInheritValue ? nil : value }
    }
    func utilityHarnessLabel(_ value: String) -> String {
        value == Self.pullRequestReviewInheritValue
            ? "Threads default (\(harnessDisplayName(for: settingsService.current.defaultHarness)))"
            : harnessDisplayName(for: value)
    }
    func utilityModelLabel(_ value: String) -> String {
        value == Self.pullRequestReviewInheritValue ? "Default" : modelLabel(for: value, harnessId: utilityHarnessID)
    }
    func utilityEffortLabel(_ value: String) -> String {
        if value == Self.pullRequestReviewInheritValue { return utilityHarnessID == "opencode" ? "Follow defaults" : "Default" }
        let fallback = utilityHarnessID == "opencode" ? AppSettings.openCodeNativeEffort(stored: value) ?? "Default"
            : ChatComposerTextSupport.effortLabel(for: value)
        return utilityModelEffortOptions.first { $0.value == value }?.label ?? fallback
    }
    private var utilityModelEffortOptions: [AgentHarnessOption] {
        if utilityHarnessID == "opencode" {
            guard let model = utilityOpenCodeModel else { return [] }
            if model.supportedEffortOptions.isEmpty {
                return [.init(value: AppSettings.openCodeDefaultEffort, label: "Default", description: "Use the model's configured defaults.")]
            }
            return AgentModelOptionSelection.effortOptions(in: [model], selectedModel: model.id)
        }
        return AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: utilityHarnessID), selectedModel: settingsService.current.effectiveUtilityModel
        )
    }

    private var utilityOpenCodeModel: AgentModelOption? {
        guard utilityHarnessID == "opencode" else { return nil }
        let selection = settingsService.current.effectiveUtilityModel
        return modelOptions(for: utilityHarnessID).first { $0.model != nil && ($0.id == selection || $0.model == selection) }
    }
}
