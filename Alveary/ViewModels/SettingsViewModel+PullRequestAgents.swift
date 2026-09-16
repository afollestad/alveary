import AgentCLIKit
import SwiftUI

/// Each route owns its pins; the editor shares only harness-dependent picker behavior.
extension SettingsViewModel {
    var reviewAgentEditor: PullRequestAgentSettingsEditor {
        PullRequestAgentSettingsEditor(viewModel: self, path: \.pullRequestReviewAgent)
    }

    var addressFeedbackEffectiveHarnessID: String { feedbackAgentEditor.effectiveHarnessID }
    var addressFeedbackHarnessSelection: String { feedbackAgentEditor.harnessSelection }
    var addressFeedbackHarnessOptions: [String] { feedbackAgentEditor.harnessOptions }
    var addressFeedbackModelSelection: String { feedbackAgentEditor.modelSelection }
    var addressFeedbackModelOptions: [String] { feedbackAgentEditor.modelOptions }
    var addressFeedbackEffortSelection: String { feedbackAgentEditor.effortSelection }
    var addressFeedbackEffortOptions: [AgentHarnessOption] { feedbackAgentEditor.effortOptions }
    var addressFeedbackPermissionSelection: String { feedbackAgentEditor.permissionSelection }
    var addressFeedbackPermissionOptions: [String] { feedbackAgentEditor.permissionOptions }

    func setAddressFeedbackHarness(_ value: String) { feedbackAgentEditor.setHarness(value) }
    func setAddressFeedbackModel(_ value: String) { feedbackAgentEditor.setModel(value) }
    func setAddressFeedbackEffort(_ value: String) { feedbackAgentEditor.setEffort(value) }
    func setAddressFeedbackPermission(_ value: String) { feedbackAgentEditor.setPermission(value) }

    func addressFeedbackLabel(forHarness value: String) -> String { feedbackAgentEditor.label(forHarness: value) }
    func addressFeedbackLabel(forModel value: String) -> String { feedbackAgentEditor.label(forModel: value) }
    func addressFeedbackLabel(forEffort value: String) -> String { feedbackAgentEditor.label(forEffort: value) }
    func addressFeedbackLabel(forPermission value: String) -> String { feedbackAgentEditor.label(forPermission: value) }

    private var feedbackAgentEditor: PullRequestAgentSettingsEditor {
        PullRequestAgentSettingsEditor(viewModel: self, path: \.pullRequestAddressFeedbackAgent)
    }
}

/// A value adapter keeps edits in the view model and applies dependent resets atomically to one route.
@MainActor
struct PullRequestAgentSettingsEditor {
    let viewModel: SettingsViewModel
    let path: WritableKeyPath<AppSettings, PullRequestAgentSettings>

    var effectiveHarnessID: String {
        if settings.harness == "opencode" { return "opencode" }
        guard let pinned = settings.harness, viewModel.threadDefaultHarnessIDs.contains(pinned) else {
            return viewModel.threadDefaultHarnessSelection
        }
        return pinned
    }

    var harnessSelection: String { settings.harness ?? inheritValue }
    var harnessOptions: [String] { [inheritValue] + viewModel.threadDefaultHarnessIDs }

    /// Model, effort, and permissions are harness-scoped, so changing harnesses clears their pins.
    func setHarness(_ value: String) {
        update {
            $0.harness = value == inheritValue ? nil : value
            $0.model = nil
            $0.effort = nil
            $0.permissionMode = nil
        }
    }

    var modelSelection: String {
        guard let stored = settings.model else { return inheritValue }
        return AgentModelOptionSelection.pickerValue(
            in: viewModel.modelOptions(for: effectiveHarnessID),
            matching: stored
        )
    }

    var modelOptions: [String] {
        [inheritValue] + viewModel.modelOptionValues(for: effectiveHarnessID).filter { $0 != inheritValue }
    }

    func setModel(_ value: String) {
        guard value != inheritValue else {
            update {
                $0.model = nil
                $0.effort = nil
            }
            return
        }
        let options = viewModel.modelOptions(for: effectiveHarnessID)
        let storedModel = AgentModelOptionSelection.storedModelValue(in: options, matching: value)
        let usesNativeVariants = effectiveHarnessID == "opencode"
        update { agent in
            agent.model = storedModel
            let supported = AgentModelOptionSelection.effortOptions(in: options, selectedModel: storedModel)
            if usesNativeVariants, !supported.contains(where: { $0.value == agent.effort }) {
                agent.effort = AppSettings.openCodeDefaultEffort
            } else if let effort = agent.effort, !supported.isEmpty, !supported.contains(where: { $0.value == effort }) {
                agent.effort = nil
            }
        }
    }

    var effortSelection: String {
        guard let stored = settings.effort else { return inheritValue }
        return effectiveHarnessID == "opencode" ? AppSettings.openCodePickerEffort(stored: stored) : stored
    }

    var effortOptions: [AgentHarnessOption] {
        AgentModelOptionSelection.effortOptions(
            in: viewModel.modelOptions(for: effectiveHarnessID),
            selectedModel: settings.model ?? (effectiveHarnessID == viewModel.settingsService.current.defaultHarness
                ? viewModel.settingsService.current.defaultModel : nil)
        )
    }

    func setEffort(_ value: String) {
        update { $0.effort = value == inheritValue ? nil : value }
    }

    /// Unsupported pins display the inherited choice without mutating settings during a read.
    var permissionSelection: String {
        guard let stored = settings.permissionMode, permissionOptions.contains(stored) else { return inheritValue }
        return stored
    }

    var permissionOptions: [String] {
        [inheritValue] + viewModel.permissionModeOptions(for: effectiveHarnessID)
    }

    func setPermission(_ value: String) {
        update { $0.permissionMode = value == inheritValue ? nil : value }
    }

    func label(forHarness value: String) -> String {
        value == inheritValue ? "Default" : viewModel.harnessDisplayName(for: value)
    }

    func label(forModel value: String) -> String {
        value == inheritValue ? "Default" : viewModel.modelLabel(for: value, harnessId: effectiveHarnessID)
    }

    func label(forEffort value: String) -> String {
        guard value != inheritValue else { return effectiveHarnessID == "opencode" ? "Follow defaults" : "Default" }
        let fallback = effectiveHarnessID == "opencode" ? AppSettings.openCodeNativeEffort(stored: value) ?? "Default"
            : ChatComposerTextSupport.effortLabel(for: value)
        return effortOptions.first { $0.value == value }?.label ?? fallback
    }

    func label(forPermission value: String) -> String {
        guard value != inheritValue else { return "Use thread default" }
        let harness = effectiveHarnessID
        let label = viewModel.permissionModeLabel(for: value, harnessId: harness)
        // A concrete harness default is different from inheriting Threads settings.
        return label == "Default" ? "Default (\(viewModel.harnessDisplayName(for: harness)))" : label
    }

    private var inheritValue: String { SettingsViewModel.pullRequestReviewInheritValue }
    private var settings: PullRequestAgentSettings { viewModel.settingsService.current[keyPath: path] }

    private func update(_ transform: (inout PullRequestAgentSettings) -> Void) {
        viewModel.settingsService.update { transform(&$0[keyPath: path]) }
    }
}
