import AgentCLIKit
import SwiftUI

/// Keeps installation details outside the toggle's hit target so paths stay selectable
/// and setup actions cannot accidentally disable the harness.
struct SettingsAgentCard: View {
    let viewModel: SettingsViewModel
    let harnessID: String

    /// Optional so a snapshot host mounted without the app root renders the card with no Sign In
    /// action rather than failing to resolve.
    @Environment(HarnessSignInService.self) private var harnessSignIn: HarnessSignInService?
    @Environment(TerminalManager.self) private var terminalManager: TerminalManager?
    @Environment(AppState.self) private var appState: AppState?

    var body: some View {
        SettingsFormSection {
            let status = viewModel.harnessStatus(for: harnessID)

            SettingsFormRow(showsDivider: false) {
                headerAndDetails(for: status)
            }
        }
    }
}

private extension SettingsAgentCard {
    func isChecking(_ status: AgentHarnessStatus?) -> Bool {
        status?.isEnabled == true && status?.installation == .unknown && status?.setup == .unknown
    }

    func headerAndDetails(for status: AgentHarnessStatus?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            toggleHeader(for: status)

            if isChecking(status) {
                Text("Checking installation status...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                detailsStack(for: status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func toggleHeader(for status: AgentHarnessStatus?) -> some View {
        SettingsToggleControl(
            "\(viewModel.harnessDisplayName(for: harnessID)) enabled",
            helpText: viewModel.shortStatusLabel(for: status),
            isOn: Binding(
                get: { viewModel.isHarnessEnabled(harnessID) },
                set: { viewModel.setHarness(harnessID, enabled: $0) }
            )
        ) { indicator in
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    harnessName
                    Spacer(minLength: 8)
                    statusIndicator(for: status)
                    indicator.fixedSize()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        harnessName
                        Spacer(minLength: 8)
                        indicator.fixedSize()
                    }
                    statusIndicator(for: status)
                }
            }
        }
    }

    var harnessName: some View {
        Text(viewModel.harnessDisplayName(for: harnessID))
            .font(.headline)
            .fixedSize()
    }

    @ViewBuilder
    func statusIndicator(for status: AgentHarnessStatus?) -> some View {
        if isChecking(status) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking installation status")
        } else {
            AgentStatusBadge(
                text: viewModel.shortStatusLabel(for: status),
                color: viewModel.statusColor(for: status)
            )
            .fixedSize()
        }
    }

    func detailsStack(for status: AgentHarnessStatus?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            versionAndPathLine(for: status)

            if viewModel.showsStatusDescription(for: status) {
                Text(viewModel.statusDescription(for: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            installCommandSection(for: status)

            diagnosticsSection(for: status)

            if viewModel.isHarnessEnabled(harnessID), status?.isEnabled == true,
               status?.installation == .installed, status?.setup == .failed {
                Text("After updating or fixing \(viewModel.harnessDisplayName(for: harnessID)), use Refresh above to check again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            signInSection(for: status)
        }
    }

    /// Sign In for an installed harness whose credential needs renewing. Gated the same way as
    /// `installCommandSection`: the state it fixes, plus a registry command to fix it with.
    @ViewBuilder
    func signInSection(for status: AgentHarnessStatus?) -> some View {
        if status?.installation == .installed,
           status?.setup == .needsSetup,
           viewModel.signInCommand(for: harnessID) != nil,
           let harnessSignIn,
           let terminalManager {
            Button("Sign In") {
                guard harnessSignIn.startSignIn(harnessID: harnessID, terminalManager: terminalManager) else {
                    return
                }
                appState?.showTerminalPane()
            }
            .secondaryActionButtonStyle()
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    func versionAndPathLine(for status: AgentHarnessStatus?) -> some View {
        let version = viewModel.harnessVersion(for: status)
        let path = viewModel.harnessExecutablePath(for: status)

        if version != nil || path != nil {
            versionAndPathText(version: version, path: path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path ?? version ?? "")
        }
    }

    func versionAndPathText(version: String?, path: String?) -> Text {
        switch (version, path) {
        case let (version?, path?):
            return Text("\(version) · \(Text(path).font(.caption.monospaced()))")
        case let (version?, nil):
            return Text(version)
        case let (nil, path?):
            return Text(path).font(.caption.monospaced())
        case (nil, nil):
            return Text("")
        }
    }

    @ViewBuilder
    func installCommandSection(for status: AgentHarnessStatus?) -> some View {
        if status?.installation == .missing, let installCommand = viewModel.installCommand(for: harnessID) {
            Text(installCommand)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    func diagnosticsSection(for status: AgentHarnessStatus?) -> some View {
        if let status, !status.diagnostics.isEmpty {
            ForEach(status.diagnostics, id: \.self) { diagnostic in
                Text(diagnostic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct AgentStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}
