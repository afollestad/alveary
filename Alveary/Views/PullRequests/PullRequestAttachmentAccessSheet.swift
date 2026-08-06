import SwiftUI

/// Guidance sheet for a `sessionUnavailable` attachment upload failure: the
/// `gh image` extension could not read a GitHub browser session. Walks the two
/// remedies — granting Alveary Full Disk Access so Safari's cookie store is
/// readable, or signing in to GitHub in Chrome — and offers a retry.
struct PullRequestAttachmentAccessSheet: View {
    let onOpenSettings: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    /// Whether Safari's cookie store is currently readable; injectable so
    /// snapshots pin both states.
    let probeSafariAccess: () -> Bool

    @State private var isSafariCookieStoreReadable: Bool

    init(
        onOpenSettings: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        probeSafariAccess: @escaping () -> Bool = GitHubAttachmentAccessGuide.canReadSafariCookieStore
    ) {
        self.onOpenSettings = onOpenSettings
        self.onRetry = onRetry
        self.onCancel = onCancel
        self.probeSafariAccess = probeSafariAccess
        // Probing at construction also registers Alveary in the Full Disk
        // Access pane's app list, so granting is a toggle, not a "+" hunt.
        _isSafariCookieStoreReadable = State(initialValue: probeSafariAccess())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Can't read your GitHub session")
                    .font(.title3.weight(.semibold))
                Text(
                    """
                    GitHub only accepts attachment uploads from a signed-in browser session — a GitHub CLI \
                    token can't do it. Alveary reads that session from a browser's cookie store.
                    """
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            safariRemedy

            chromeRemedy

            footer
        }
        .padding(24)
        .frame(width: 460)
        .task(pollSafariAccess)
    }

    private var safariRemedy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Option 1: Let Alveary read Safari's cookies")
                .fontWeight(.semibold)
            Text(
                """
                Safari's cookies are protected by Full Disk Access. Turn on Alveary under \
                Privacy & Security → Full Disk Access — add it with the + button if it isn't \
                listed — then try again.
                """
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    ActionButtonLabel(title: "Open System Settings", icon: .system("gearshape"))
                }
                .secondaryActionButtonStyle()
                if isSafariCookieStoreReadable {
                    Label("Access granted", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var chromeRemedy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Option 2: Sign in with Chrome")
                .fontWeight(.semibold)
            Text(
                """
                Sign in to github.com in Chrome. The next upload asks once for Keychain access \
                to Chrome's cookie store — no Full Disk Access needed.
                """
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button(action: onCancel) {
                ActionButtonLabel(title: "Cancel", icon: .system("xmark"))
            }
            .secondaryActionButtonStyle()
            .keyboardShortcut(.cancelAction)
            Button(action: onRetry) {
                ActionButtonLabel(title: "Try Again", icon: .system("arrow.clockwise"))
            }
            .primaryActionButtonStyle()
            .keyboardShortcut(.defaultAction)
        }
    }

    /// Flips the "Access granted" cue live while the sheet is up, so returning
    /// from System Settings confirms the toggle worked before retrying.
    @Sendable
    private func pollSafariAccess() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            isSafariCookieStoreReadable = probeSafariAccess()
        }
    }
}
