import AppKit
import SwiftUI

struct GitSettingsTabView: View {
    let gitHubCLI: GitHubCLIService
    /// The agentic agent pickers read provider discovery through the view model, the way
    /// the Threads tab's defaults do.
    let viewModel: SettingsViewModel
    @Binding var branchPrefix: String
    @Binding var commitMessageGenerationPrompt: String
    @Binding var pullRequestGenerationPrompt: String
    @Binding var pullRequestReviewPrompt: String
    @Binding var pullRequestAddressFeedbackPrompt: String
    @Binding var worktreesBaseDirectory: String
    @Binding var createWorktreeByDefault: Bool
    @Binding var pullRequestsEnabled: Bool
    @Binding var automaticallyLinkPullRequests: Bool

    @State private var gitHubInstalledVersion: String?
    @State private var isGitHubConnected = false
    @State private var isGitHubAuthenticating = false
    @State private var gitHubDeviceCode: GitHubDeviceCode?
    @State private var screenError: String?
    @State private var isReviewTeamEditorPresented = false
    @State private var reviewTeamDraftSettings = AppSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let screenError {
                InlineBanner(
                    message: screenError,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: { self.screenError = nil }
                )
            }

            VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
                SettingsFormSection("Branching") {
                    SettingsFormRow(showsDivider: false) {
                        SettingsTextFieldRow(
                            "Branch prefix",
                            text: $branchPrefix,
                            horizontalControlSizing: .expandsToFitText
                        )
                    }
                }

                SettingsFormSection("Commits") {
                    SettingsPromptEditorRow(
                        "Commit message generation prompt",
                        helpText: GitSettingsHelp.commitMessageGenerationPrompt,
                        prompt: $commitMessageGenerationPrompt,
                        defaultPrompt: AppSettings.defaultCommitMessageGenerationPrompt,
                        placeholder: "Write the prompt used to generate commit messages.",
                        showsDivider: false
                    )
                }

                SettingsFormSection("GitHub") {
                    SettingsFormRow(showsDivider: false) {
                        gitHubSection
                    }
                }

                SettingsFormSection("Pull requests") {
                    SettingsFormSubsectionHeader("General", isFirstInSection: true)

                    SettingsToggleRow(
                        "Enable pull request integration",
                        helpText: GitSettingsHelp.pullRequestsEnabled,
                        isOn: $pullRequestsEnabled
                    )

                    SettingsToggleRow(
                        "Automatically link PRs",
                        helpText: GitSettingsHelp.automaticallyLinkPullRequests,
                        isOn: $automaticallyLinkPullRequests,
                        isDisabled: !pullRequestsEnabled
                    )

                    SettingsPromptEditorRow(
                        "Pull request generation prompt",
                        helpText: GitSettingsHelp.pullRequestGenerationPrompt,
                        prompt: $pullRequestGenerationPrompt,
                        defaultPrompt: AppSettings.defaultPullRequestGenerationPrompt,
                        placeholder: "Write the prompt used to generate pull request titles and descriptions.",
                        showsDivider: false
                    )

                    SettingsFormSubsectionHeader("Address feedback")

                    SettingsPromptEditorRow(
                        "Address feedback instructions",
                        helpText: GitSettingsHelp.pullRequestAddressFeedbackPrompt,
                        prompt: $pullRequestAddressFeedbackPrompt,
                        defaultPrompt: AppSettings.defaultPullRequestAddressFeedbackPrompt,
                        placeholder: "Write the instructions the agent follows when addressing feedback on a pull request."
                    )

                    sidebarSectionRow(
                        accessibilityLabel: "Address feedback sidebar section",
                        helpText: GitSettingsHelp.pullRequestAddressFeedbackSection,
                        selection: Binding(
                            get: { viewModel.pullRequestAddressFeedbackSection },
                            set: { viewModel.setPullRequestAddressFeedbackSection($0) }
                        ),
                        showsDivider: true
                    )

                    PullRequestAgentSettingsRows(viewModel: viewModel, route: .addressFeedback)

                    SettingsFormSubsectionHeader("Agentic review")

                    SettingsPromptEditorRow(
                        "Review criteria",
                        helpText: GitSettingsHelp.pullRequestReviewPrompt,
                        prompt: $pullRequestReviewPrompt,
                        defaultPrompt: AppSettings.defaultPullRequestReviewPrompt,
                        placeholder: "Write the criteria agents use when reviewing a pull request."
                    )

                    SettingsFormRow {
                        SettingsResponsiveControlRow(
                            "Review mode",
                            helpText: GitSettingsHelp.pullRequestReviewMode,
                            horizontalControlSizing: .intrinsic
                        ) {
                            SettingsTwoButtonToggle(
                                "Review mode",
                                selection: Binding(
                                    get: { viewModel.pullRequestReviewMode },
                                    set: { viewModel.setPullRequestReviewMode($0) }
                                ),
                                first: .singleAgent,
                                second: .reviewTeam,
                                label: { $0 == .singleAgent ? "Single agent" : "Review team" }
                            )
                        }
                    }

                    if viewModel.pullRequestReviewMode == .reviewTeam {
                        reviewTeamRow
                    } else {
                        PullRequestAgentSettingsRows(viewModel: viewModel, route: .review, showsFinalDivider: true)
                    }

                    sidebarSectionRow(
                        accessibilityLabel: "Agentic review sidebar section",
                        helpText: GitSettingsHelp.pullRequestReviewSection,
                        selection: Binding(
                            get: { viewModel.pullRequestReviewSection },
                            set: { viewModel.setPullRequestReviewSection($0) }
                        ),
                        showsDivider: false
                    )
                }

                SettingsFormSection("Worktrees") {
                    SettingsToggleRow(
                        "Create worktree by default",
                        helpText: GitSettingsHelp.createWorktreeByDefault,
                        isOn: $createWorktreeByDefault
                    )

                    SettingsFormRow(showsDivider: false) {
                        SettingsFolderPickerRow("Worktrees directory", path: $worktreesBaseDirectory)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            viewModel.refreshSidebarSectionOptions()
            await refreshGitHubState()
            // The agent pickers below need the same provider catalog the Threads tab loads.
            await viewModel.refreshProviderStatusesIfNeeded()
        }
        .sheet(isPresented: $isReviewTeamEditorPresented) {
            PullRequestReviewTeamEditorSheet(
                viewModel: viewModel,
                draft: reviewTeamDraftSettings,
                onCancel: { isReviewTeamEditorPresented = false },
                onSave: { draft in
                    viewModel.setPullRequestReviewTeam(draft)
                    isReviewTeamEditorPresented = false
                }
            )
        }
    }
}

private extension GitSettingsTabView {
    var reviewTeamRow: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow(
                "Review team",
                helpText: GitSettingsHelp.pullRequestReviewTeam,
                horizontalControlSizing: .selectedContent
            ) {
                HStack(spacing: 10) {
                    Text(reviewTeamSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button("Manage", action: presentReviewTeamEditor)
                        .secondaryActionButtonStyle()
                        .disabled(viewModel.isCheckingThreadDefaultProviders)
                }
            }
        }
    }

    var reviewTeamSummary: String {
        let summary = viewModel.pullRequestReviewTeamSummary
        guard viewModel.pullRequestReviewMode == .reviewTeam || !viewModel.pullRequestReviewPeers.isEmpty else {
            return summary
        }
        switch viewModel.pullRequestReviewTeamSettingsStatus {
        case .checking:
            return "\(summary) · Checking"
        case .ready:
            return summary
        case .needsAttention:
            return "\(summary) · Needs attention"
        }
    }

    func presentReviewTeamEditor() {
        reviewTeamDraftSettings = viewModel.reviewTeamEditorSettings()
        isReviewTeamEditorPresented = true
    }

    /// Where one agentic route's spawned thread lands in the sidebar. The row stays visible with no custom sections rather
    /// than disappearing, so the setting is discoverable before there is anything to pick — but
    /// disabled, because `Tasks` alone is no choice. `SettingsMenuPicker` disables itself only on
    /// an empty option list, and `Tasks` is always in this one.
    ///
    /// Both rows read "Sidebar section" on screen, where the sub-header above says which route
    /// they belong to. VoiceOver announces the control alone, so the picker takes a
    /// route-qualified name instead — two identically named controls in one card are
    /// indistinguishable by ear.
    @ViewBuilder
    func sidebarSectionRow(
        accessibilityLabel: String,
        helpText: String,
        selection: Binding<String?>,
        showsDivider: Bool = true
    ) -> some View {
        SettingsFormRow(showsDivider: showsDivider) {
            SettingsResponsiveControlRow(
                "Sidebar section",
                helpText: helpText,
                horizontalControlSizing: .selectedContent
            ) {
                SettingsMenuPicker(
                    accessibilityLabel,
                    selection: selection,
                    options: viewModel.pullRequestSectionOptions,
                    isDisabled: viewModel.sidebarSectionOptions.isEmpty,
                    label: { viewModel.pullRequestSectionLabel(for: $0) }
                )
            }
        }
    }

    @ViewBuilder
    var gitHubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let gitHubDeviceCode {
                Text("Enter the one-time code below in GitHub to finish connecting.")
                    .foregroundStyle(.secondary)

                HStack {
                    Text(gitHubDeviceCode.code)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)

                    Spacer()

                    Button("Open Browser", action: openBrowser)
                        .secondaryActionButtonStyle()
                }
            } else if isGitHubConnected {
                Label("Connected for GitHub project metadata.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if gitHubInstalledVersion == nil {
                Text("Install the GitHub CLI to show GitHub project connection state.")
                    .foregroundStyle(.secondary)

                Text("brew install gh")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("Connect GitHub to show authenticated project connection state.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                if gitHubInstalledVersion != nil && !isGitHubConnected {
                    Button(isGitHubAuthenticating ? "Connecting..." : "Connect GitHub") {
                        Task { await connectGitHub() }
                    }
                    .primaryActionButtonStyle()
                    .disabled(isGitHubAuthenticating)
                }

                if let gitHubInstalledVersion {
                    Text(gitHubInstalledVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    func openBrowser() {
        guard let verificationURL = gitHubDeviceCode?.verificationURL else {
            return
        }
        NSWorkspace.shared.open(verificationURL)
    }

    func refreshGitHubState() async {
        let installedVersion = await gitHubCLI.checkInstalled()
        gitHubInstalledVersion = installedVersion
        guard installedVersion != nil else {
            isGitHubConnected = false
            return
        }
        isGitHubConnected = await gitHubCLI.isAuthenticated()
    }

    func connectGitHub() async {
        guard !isGitHubAuthenticating else {
            return
        }

        isGitHubAuthenticating = true
        defer { isGitHubAuthenticating = false }

        do {
            let deviceCode = try await gitHubCLI.authenticate()
            gitHubDeviceCode = deviceCode
            NSWorkspace.shared.open(deviceCode.verificationURL)

            let didAuthenticate = try await gitHubCLI.awaitAuthentication()
            gitHubDeviceCode = nil
            guard didAuthenticate else {
                screenError = "GitHub authentication did not complete."
                return
            }

            isGitHubConnected = true
        } catch {
            gitHubDeviceCode = nil
            screenError = error.localizedDescription
        }
    }
}

private enum GitSettingsHelp {
    static let commitMessageGenerationPrompt =
        "Prompt sent to the agent when generating a commit message from the Git commit modal."
    static let createWorktreeByDefault =
        "New threads default to creating a worktree instead of using the main project folder. You can override this in the composer."
    static let pullRequestsEnabled =
        "Show the \"Pull requests\" sidebar row and the toolbar button for linking pull requests to a thread."
    static let automaticallyLinkPullRequests =
        "Link pull requests to the thread as soon as their GitHub link appears in a message, instead of asking in the transcript."
    static let pullRequestGenerationPrompt =
        "Prompt sent to the agent when generating a pull request title or description left blank in the create pull request modal."
    static let pullRequestReviewPrompt =
        "Criteria every reviewer uses to evaluate a pull request and write feedback. Alveary owns the review workflow and proposal staging."
    static let pullRequestReviewMode =
        "Single uses the lead agent. Team runs the lead and saved peers independently, then proposes only feedback a strict majority supports."
    static let pullRequestReviewTeam =
        "One saved team of 2–5 distinct agent and concrete-model pairs. Settings changes apply to the next review."
    static let pullRequestAddressFeedbackPrompt =
        "Instructions the agent follows when addressing feedback on a pull request — one started by "
        + "\"Address feedback\" in a pull request's footer, or any thread you ask to address feedback. "
        + "It reads the feedback, changes the code where the feedback holds up, then replies and resolves the threads."
    static let pullRequestAddressFeedbackSection =
        "Sidebar section the thread \"Address feedback\" creates lands in. It seeds that new thread only — "
        + "moving a thread afterwards is a drag in the sidebar."
    static let pullRequestReviewSection =
        "Sidebar section the thread \"Agentic review\" creates lands in. It seeds that new thread only — "
        + "moving a thread afterwards is a drag in the sidebar."
}
