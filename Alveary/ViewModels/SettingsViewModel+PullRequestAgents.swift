import AgentCLIKit
import SwiftUI

/// Each route owns its pins; the editor shares only provider-dependent picker behavior.
extension SettingsViewModel {
    var reviewAgentEditor: PullRequestAgentSettingsEditor {
        PullRequestAgentSettingsEditor(viewModel: self, path: \.pullRequestReviewAgent)
    }

    var addressFeedbackEffectiveProviderID: String { feedbackAgentEditor.effectiveProviderID }
    var addressFeedbackProviderSelection: String { feedbackAgentEditor.providerSelection }
    var addressFeedbackProviderOptions: [String] { feedbackAgentEditor.providerOptions }
    var addressFeedbackModelSelection: String { feedbackAgentEditor.modelSelection }
    var addressFeedbackModelOptions: [String] { feedbackAgentEditor.modelOptions }
    var addressFeedbackEffortSelection: String { feedbackAgentEditor.effortSelection }
    var addressFeedbackEffortOptions: [AgentProviderOption] { feedbackAgentEditor.effortOptions }
    var addressFeedbackPermissionSelection: String { feedbackAgentEditor.permissionSelection }
    var addressFeedbackPermissionOptions: [String] { feedbackAgentEditor.permissionOptions }

    func setAddressFeedbackProvider(_ value: String) { feedbackAgentEditor.setProvider(value) }
    func setAddressFeedbackModel(_ value: String) { feedbackAgentEditor.setModel(value) }
    func setAddressFeedbackEffort(_ value: String) { feedbackAgentEditor.setEffort(value) }
    func setAddressFeedbackPermission(_ value: String) { feedbackAgentEditor.setPermission(value) }

    func addressFeedbackLabel(forProvider value: String) -> String { feedbackAgentEditor.label(forProvider: value) }
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

    var effectiveProviderID: String {
        guard let pinned = settings.provider, viewModel.threadDefaultProviderIDs.contains(pinned) else {
            return viewModel.threadDefaultProviderSelection
        }
        return pinned
    }

    var providerSelection: String { settings.provider ?? inheritValue }
    var providerOptions: [String] { [inheritValue] + viewModel.threadDefaultProviderIDs }

    /// Model, effort, and permissions are provider-scoped, so changing providers clears their pins.
    func setProvider(_ value: String) {
        update {
            $0.provider = value == inheritValue ? nil : value
            $0.model = nil
            $0.effort = nil
            $0.permissionMode = nil
        }
    }

    var modelSelection: String {
        guard let stored = settings.model else { return inheritValue }
        return AgentModelOptionSelection.pickerValue(
            in: viewModel.modelOptions(for: effectiveProviderID),
            matching: stored
        )
    }

    var modelOptions: [String] {
        [inheritValue] + viewModel.modelOptionValues(for: effectiveProviderID).filter { $0 != inheritValue }
    }

    func setModel(_ value: String) {
        guard value != inheritValue else {
            update {
                $0.model = nil
                $0.effort = nil
            }
            return
        }
        let options = viewModel.modelOptions(for: effectiveProviderID)
        let storedModel = AgentModelOptionSelection.storedModelValue(in: options, matching: value)
        update {
            $0.model = storedModel
            let supported = AgentModelOptionSelection.effortOptions(in: options, selectedModel: storedModel)
            if let effort = $0.effort, !supported.isEmpty, !supported.contains(where: { $0.value == effort }) {
                $0.effort = nil
            }
        }
    }

    var effortSelection: String { settings.effort ?? inheritValue }

    var effortOptions: [AgentProviderOption] {
        AgentModelOptionSelection.effortOptions(
            in: viewModel.modelOptions(for: effectiveProviderID),
            selectedModel: settings.model
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
        [inheritValue] + viewModel.permissionModeOptions(for: effectiveProviderID)
    }

    func setPermission(_ value: String) {
        update { $0.permissionMode = value == inheritValue ? nil : value }
    }

    func label(forProvider value: String) -> String {
        value == inheritValue ? "Default" : viewModel.providerDisplayName(for: value)
    }

    func label(forModel value: String) -> String {
        value == inheritValue ? "Default" : viewModel.modelLabel(for: value, providerId: effectiveProviderID)
    }

    func label(forEffort value: String) -> String {
        guard value != inheritValue else { return "Default" }
        return effortOptions.first { $0.value == value }?.label ?? ChatComposerTextSupport.effortLabel(for: value)
    }

    func label(forPermission value: String) -> String {
        guard value != inheritValue else { return "Use thread default" }
        let provider = effectiveProviderID
        let label = viewModel.permissionModeLabel(for: value, providerId: provider)
        // A concrete provider default is different from inheriting Threads settings.
        return label == "Default" ? "Default (\(viewModel.providerDisplayName(for: provider)))" : label
    }

    private var inheritValue: String { SettingsViewModel.pullRequestReviewInheritValue }
    private var settings: PullRequestAgentSettings { viewModel.settingsService.current[keyPath: path] }

    private func update(_ transform: (inout PullRequestAgentSettings) -> Void) {
        viewModel.settingsService.update { transform(&$0[keyPath: path]) }
    }
}
