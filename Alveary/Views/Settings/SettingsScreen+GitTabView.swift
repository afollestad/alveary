import AppKit
import SwiftUI

struct GitSettingsTabView: View {
    let gitHubCLI: GitHubCLIService
    @Binding var branchPrefix: String
    @Binding var worktreesBaseDirectory: String
    @Binding var pushOnCreate: Bool

    @State private var gitHubInstalledVersion: String?
    @State private var isGitHubConnected = false
    @State private var isGitHubAuthenticating = false
    @State private var gitHubDeviceCode: GitHubDeviceCode?
    @State private var screenError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let screenError {
                InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                    self.screenError = nil
                }
            }

            VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
                SettingsFormSection("Branching") {
                    SettingsFormRow {
                        SettingsTextFieldRow(
                            "Branch prefix",
                            text: $branchPrefix,
                            horizontalControlSizing: .expandsToFitText
                        )
                    }

                    SettingsToggleRow("Push on create", isOn: $pushOnCreate, showsDivider: false)
                }

                SettingsFormSection("Worktrees") {
                    SettingsFormRow(showsDivider: false) {
                        SettingsFolderPickerRow("Worktrees directory", path: $worktreesBaseDirectory)
                    }
                }

                SettingsFormSection("GitHub") {
                    SettingsFormRow(showsDivider: false) {
                        gitHubSection
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refreshGitHubState()
        }
    }
}

private extension GitSettingsTabView {
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
                Label("Connected for PR and CI workflows.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if gitHubInstalledVersion == nil {
                Text("Install the GitHub CLI to enable PR and CI features.")
                    .foregroundStyle(.secondary)

                Text("brew install gh")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("Connect GitHub for PR, CI, and agent-opened pull requests.")
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
