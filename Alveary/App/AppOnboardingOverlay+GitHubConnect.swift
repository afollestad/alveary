import SwiftUI

/// Sits under the GitHub CLI row once `gh` is installed. Signing in is optional here — Continue
/// never waits on it — but doing it now avoids failures later in pull requests, updates, and clones.
struct AppOnboardingGitHubConnect: View {
    let state: OnboardingGitHubAuthState
    let onConnect: () -> Void
    let onOpenBrowser: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .checking:
                Text("Checking GitHub sign-in...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .notConnected:
                connectPrompt(message: "Sign in to GitHub to browse pull requests and clone private repositories.")

            case .connecting(let deviceCode):
                if let deviceCode {
                    deviceCodePrompt(deviceCode)
                } else {
                    Text("Starting GitHub sign-in...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .failed(let message):
                connectPrompt(message: message, isError: true)

            case .unknown, .connected:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectPrompt(message: String, isError: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(message)
                .font(.caption)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(isError ? "Try Again" : "Connect GitHub", action: onConnect)
                .secondaryActionButtonStyle()
        }
    }

    private func deviceCodePrompt(_ deviceCode: GitHubDeviceCode) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter this code at \(deviceCode.verificationURL.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(deviceCode.code)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Open Browser", action: onOpenBrowser)
                .secondaryActionButtonStyle()
        }
    }
}
