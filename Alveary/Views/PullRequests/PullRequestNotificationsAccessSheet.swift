import SwiftUI

/// Asks for the GitHub CLI's `notifications` scope, which ignoring a pull request needs to
/// unsubscribe from it. Explains first and launches nothing until Continue; the browser opens
/// only from Open GitHub, once the code is on screen.
///
/// `Equatable` and fed the request by value, so snapshots host it directly; the actions are
/// excluded from `==` because each only calls into the coordinator.
struct PullRequestNotificationsAccessSheet: View, Equatable {
    let request: PullRequestNotificationsAccessRequest
    let onContinue: () -> Void
    let onOpenBrowser: () -> Void
    let onCopyCode: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    nonisolated static func == (lhs: PullRequestNotificationsAccessSheet, rhs: PullRequestNotificationsAccessSheet) -> Bool {
        lhs.request == rhs.request
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .secondaryActionButtonStyle()
                    .keyboardShortcut(.cancelAction)
                primaryButton
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }

    private var title: String {
        switch request.phase {
        case .explain, .failed:
            return "Allow notification access"
        case .requestingCode, .code:
            return "Approve on GitHub"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch request.phase {
        case .explain:
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Ignoring a pull request also unsubscribes you from its GitHub notifications. That needs "
                        + "the GitHub CLI's notifications permission, which signing in doesn't grant by default."
                )
                Text(
                    "GitHub will ask you to approve adding it to your existing gh sign-in. "
                        + "The gh command line gets it too."
                )
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .requestingCode:
            HStack(spacing: 8) {
                StatusIndicatorSpinner(color: .secondary, diameter: 12)
                    .accessibilityHidden(true)
                Text("Getting a code from GitHub…")
                    .foregroundStyle(.secondary)
            }

        case .code(let deviceCode, let didOpenBrowser):
            codeContent(deviceCode, didOpenBrowser: didOpenBrowser)

        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func codeContent(_ deviceCode: GitHubDeviceCode, didOpenBrowser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter this code at \(Self.displayAddress(of: deviceCode.verificationURL)):")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(deviceCode.code)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)

                Button(action: onCopyCode) {
                    Image(systemName: "doc.on.doc")
                }
                .iconActionButtonStyle()
                .help("Copy code")
                .accessibilityLabel("Copy code")
            }

            Text("Copied to clipboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            if didOpenBrowser {
                HStack(spacing: 8) {
                    StatusIndicatorSpinner(color: .secondary, diameter: 12)
                        .accessibilityHidden(true)
                    Text("Waiting for GitHub…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// `github.com/login/device`, without the scheme the user does not type.
    private static func displayAddress(of url: URL) -> String {
        guard let host = url.host() else {
            return url.absoluteString
        }
        return host + url.path()
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch request.phase {
        case .explain:
            Button("Continue", action: onContinue)
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
        case .requestingCode:
            Button("Open GitHub", action: {})
                .primaryActionButtonStyle()
                .disabled(true)
        case .code(_, let didOpenBrowser):
            Button(didOpenBrowser ? "Open GitHub Again" : "Open GitHub", action: onOpenBrowser)
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Try Again", action: onRetry)
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
        }
    }
}
