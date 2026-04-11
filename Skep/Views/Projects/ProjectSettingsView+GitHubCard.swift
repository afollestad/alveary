import SwiftUI

struct ProjectSettingsGitHubCard: View {
    let gitHubDeviceCode: GitHubDeviceCode?
    let isGitHubConnected: Bool
    let gitHubInstalledVersion: String?
    let isGitHubAuthenticating: Bool
    let onOpenBrowser: () -> Void
    let onConnectGitHub: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let gitHubDeviceCode {
                    Text("Enter the one-time code below in GitHub to finish connecting.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(gitHubDeviceCode.code)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)

                        Spacer()

                        Button("Open Browser", action: onOpenBrowser)
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
                        Button(isGitHubAuthenticating ? "Connecting..." : "Connect GitHub", action: onConnectGitHub)
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
        } label: {
            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
        }
    }
}
