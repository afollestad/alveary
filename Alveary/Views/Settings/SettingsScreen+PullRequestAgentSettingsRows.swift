import SwiftUI

/// Route-qualified controls keep review and feedback pins independent and distinguishable to VoiceOver.
struct PullRequestAgentSettingsRows: View {
    enum Route {
        case review
        case addressFeedback

        var label: String { self == .review ? "Review" : "Address feedback" }
    }

    let viewModel: SettingsViewModel
    let route: Route
    var showsFinalDivider = false

    var body: some View {
        pickerRow("Agent", helpText: agentHelp, selection: provider, options: providerOptions, label: providerLabel)
        pickerRow("Model", selection: model, options: modelOptions, label: modelLabel)
        if !effortOptions.isEmpty {
            pickerRow(
                "Effort",
                selection: effort,
                options: [SettingsViewModel.pullRequestReviewInheritValue] + effortOptions,
                label: effortLabel
            )
        }
        pickerRow(
            "Permission mode",
            helpText: "Permissions for \(route.label.lowercased()) tasks. Review-team workers always run read-only.",
            selection: permission,
            options: permissionOptions,
            showsDivider: showsFinalDivider,
            label: permissionLabel
        )
    }
}

private extension PullRequestAgentSettingsRows {
    var isReview: Bool { route == .review }

    var agentHelp: String {
        isReview
            ? "The agent used for single-agent reviews. In team mode, edit the lead in Manage."
            : "The agent used to address pull request feedback, independent of review settings."
    }

    var provider: Binding<String> {
        Binding(
            get: { isReview ? viewModel.pullRequestReviewProviderSelection : viewModel.addressFeedbackProviderSelection },
            set: { isReview ? viewModel.setPullRequestReviewProvider($0) : viewModel.setAddressFeedbackProvider($0) }
        )
    }

    var model: Binding<String> {
        Binding(
            get: { isReview ? viewModel.pullRequestReviewModelSelection : viewModel.addressFeedbackModelSelection },
            set: { isReview ? viewModel.setPullRequestReviewModel($0) : viewModel.setAddressFeedbackModel($0) }
        )
    }

    var effort: Binding<String> {
        Binding(
            get: { isReview ? viewModel.pullRequestReviewEffortSelection : viewModel.addressFeedbackEffortSelection },
            set: { isReview ? viewModel.setPullRequestReviewEffort($0) : viewModel.setAddressFeedbackEffort($0) }
        )
    }

    var permission: Binding<String> {
        Binding(
            get: { isReview ? viewModel.pullRequestReviewPermissionSelection : viewModel.addressFeedbackPermissionSelection },
            set: { isReview ? viewModel.setPullRequestReviewPermission($0) : viewModel.setAddressFeedbackPermission($0) }
        )
    }

    var providerOptions: [String] {
        isReview ? viewModel.pullRequestReviewProviderOptions : viewModel.addressFeedbackProviderOptions
    }

    var modelOptions: [String] {
        isReview ? viewModel.pullRequestReviewModelOptions : viewModel.addressFeedbackModelOptions
    }

    var effortOptions: [String] {
        (isReview ? viewModel.pullRequestReviewEffortOptions : viewModel.addressFeedbackEffortOptions).map(\.value)
    }

    var permissionOptions: [String] {
        isReview ? viewModel.pullRequestReviewPermissionOptions : viewModel.addressFeedbackPermissionOptions
    }

    func providerLabel(_ value: String) -> String {
        isReview ? viewModel.pullRequestReviewLabel(forProvider: value) : viewModel.addressFeedbackLabel(forProvider: value)
    }

    func modelLabel(_ value: String) -> String {
        isReview ? viewModel.pullRequestReviewLabel(forModel: value) : viewModel.addressFeedbackLabel(forModel: value)
    }

    func effortLabel(_ value: String) -> String {
        isReview ? viewModel.pullRequestReviewLabel(forEffort: value) : viewModel.addressFeedbackLabel(forEffort: value)
    }

    func permissionLabel(_ value: String) -> String {
        isReview ? viewModel.pullRequestReviewLabel(forPermission: value) : viewModel.addressFeedbackLabel(forPermission: value)
    }

    func pickerRow(
        _ title: String,
        helpText: String? = nil,
        selection: Binding<String>,
        options: [String],
        showsDivider: Bool = true,
        label: @escaping (String) -> String
    ) -> some View {
        SettingsFormRow(showsDivider: showsDivider) {
            SettingsResponsiveControlRow(title, helpText: helpText, horizontalControlSizing: .intrinsic) {
                SettingsMenuPicker("\(route.label) \(title.lowercased())", selection: selection, options: options, label: label)
            }
        }
    }
}
