import SwiftUI

struct AppUpdatesSettingsTabView: View {
    let updateManager: AppUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                AppUpdateInfoRow(
                    title: "Current version",
                    value: currentVersionText
                )

                AppUpdateInfoRow(
                    title: "Latest version",
                    value: latestVersionText
                )

                AppUpdateStatusRow(
                    presentation: statusPresentation,
                    action: statusRowAction
                )

                AppUpdateInfoRow(
                    title: "Last checked",
                    value: lastCheckedText
                )

                SettingsFormRow(showsDivider: false) {
                    HStack(spacing: 12) {
                        Button(action: checkNow) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text(updateManager.isChecking ? "Checking..." : "Check now")
                            }
                        }
                        .secondaryActionButtonStyle()
                        .disabled(updateManager.isChecking)

                        if updateManager.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }
                }
            }

            SettingsFormSection("Changelog") {
                SettingsFormRow(showsDivider: false) {
                    changelogContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension AppUpdatesSettingsTabView {
    var currentVersionText: String {
        updateManager.currentVersionString ?? updateManager.currentVersion?.description ?? "Unknown"
    }

    var latestVersionText: String {
        guard let release = displayedRelease else {
            switch updateManager.status {
            case .unavailable:
                return "Unavailable"
            default:
                return updateManager.isChecking ? "Checking..." : "Not checked"
            }
        }
        return release.version.description
    }

    var lastCheckedText: String {
        updateManager.lastCheckedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    var displayedRelease: AppUpdateRelease? {
        switch updateManager.status {
        case .updateAvailable(let release, _),
             .upToDate(let release, _):
            return release
        case .idle,
             .unavailable:
            return updateManager.latestRelease
        }
    }

    var hasDownloadableUpdate: Bool {
        switch updateManager.status {
        case .updateAvailable:
            return true
        case .idle,
             .upToDate,
             .unavailable:
            return false
        }
    }

    var canStartDownload: Bool {
        guard !updateManager.isChecking,
              case .idle = updateManager.downloadState else {
            return false
        }
        return hasDownloadableUpdate
    }

    var canRetryDownload: Bool {
        guard !updateManager.isChecking,
              case .failed = updateManager.downloadState else {
            return false
        }
        return hasDownloadableUpdate
    }

    var statusRowAction: (() -> Void)? {
        if canStartDownload || canRetryDownload {
            return downloadUpdate
        }
        if case .readyToInstall = updateManager.downloadState {
            return promptForRestart
        }
        return nil
    }

    var statusPresentation: AppUpdateStatusPresentation {
        switch updateManager.downloadState {
        case .checkingLatestRelease:
            return AppUpdateStatusPresentation(
                icon: .spinner,
                text: "Checking latest release",
                color: .secondary
            )
        case .downloading(let release, let progress):
            return AppUpdateStatusPresentation(
                icon: .spinner,
                text: "Downloading \(release.version.description)",
                color: .secondary,
                accessory: .progress(progress)
            )
        case .staging(let release):
            return AppUpdateStatusPresentation(
                icon: .spinner,
                text: "Preparing \(release.version.description)",
                color: .secondary
            )
        case .readyToInstall(let stagedUpdate):
            return AppUpdateStatusPresentation(
                icon: .system("checkmark.circle.fill"),
                text: "\(stagedUpdate.release.version.description) ready to install",
                actionText: "Click to restart",
                color: .green,
                accessibilityHint: "Shows the restart prompt."
            )
        case .installing(let stagedUpdate):
            return AppUpdateStatusPresentation(
                icon: .spinner,
                text: "Restarting to install \(stagedUpdate.release.version.description)",
                color: .secondary
            )
        case .failed(let failure):
            return AppUpdateStatusPresentation(
                icon: .system("exclamationmark.triangle.fill"),
                text: "Download failed",
                detail: failure.message,
                actionText: canRetryDownload ? "Click to retry" : nil,
                color: .orange,
                accessibilityHint: canRetryDownload ? "Retries the update download." : nil
            )
        case .idle:
            break
        }

        if updateManager.isChecking {
            return AppUpdateStatusPresentation(
                icon: .spinner,
                text: "Checking for updates",
                color: .secondary
            )
        }

        switch updateManager.status {
        case .idle:
            return AppUpdateStatusPresentation(
                icon: .system("clock"),
                text: "Not checked yet",
                color: .secondary
            )
        case .updateAvailable:
            return AppUpdateStatusPresentation(
                icon: .system("arrow.down.circle.fill"),
                text: "Update available",
                actionText: canStartDownload ? "Click to download" : nil,
                color: .blue,
                accessibilityHint: canStartDownload ? "Downloads the latest Alveary update." : nil
            )
        case .upToDate:
            return AppUpdateStatusPresentation(
                icon: .system("checkmark.circle.fill"),
                text: "Alveary is up to date",
                color: .green
            )
        case .unavailable(let reason):
            return AppUpdateStatusPresentation(
                icon: .system("exclamationmark.triangle.fill"),
                text: reason.settingsDescription,
                color: .orange
            )
        }
    }

    @ViewBuilder
    var changelogContent: some View {
        if let release = displayedRelease {
            let markdown = release.changelogMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if markdown.isEmpty {
                Text("No changelog was included with \(release.tagName).")
                    .foregroundStyle(.secondary)
            } else {
                AppMarkdownText(
                    markdown: release.changelogMarkdown,
                    baseURL: release.repositoryHTMLURL,
                    taskStateScope: "app-updates-\(release.tagName)"
                )
                .textSelection(.enabled)
            }
        } else if case .unavailable(let reason) = updateManager.status {
            Text(reason.settingsDescription)
                .foregroundStyle(.secondary)
        } else {
            Text("Check for updates to load the latest release notes.")
                .foregroundStyle(.secondary)
        }
    }

    func checkNow() {
        Task {
            await updateManager.forceCheck()
        }
    }

    func downloadUpdate() {
        Task {
            await updateManager.downloadLatestUpdate()
        }
    }

    func promptForRestart() {
        updateManager.promptForRestartIfUpdateIsReady()
    }
}

private struct AppUpdateInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        SettingsFormRow {
            HStack(spacing: 16) {
                Text(title)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 24)

                Text(value)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
            }
        }
    }
}

private struct AppUpdateStatusRow: View {
    let presentation: AppUpdateStatusPresentation
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(AppUpdateStatusRowButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status")
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityHint(presentation.accessibilityHint ?? "")
            .accessibilityAddTraits(.isButton)
        } else {
            rowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Status")
                .accessibilityValue(presentation.accessibilityValue)
        }
    }

    private var rowContent: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow(
                "Status",
                horizontalControlSizing: .fillsAvailableWidthFraction(0.72)
            ) {
                AppUpdateStatusValue(presentation: presentation)
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct AppUpdateStatusPresentation {
    let icon: AppUpdateStatusIcon
    let text: String
    let detail: String?
    let actionText: String?
    let color: Color
    let accessory: AppUpdateStatusAccessory?
    let accessibilityHint: String?

    init(
        icon: AppUpdateStatusIcon,
        text: String,
        detail: String? = nil,
        actionText: String? = nil,
        color: Color,
        accessory: AppUpdateStatusAccessory? = nil,
        accessibilityHint: String? = nil
    ) {
        self.icon = icon
        self.text = text
        self.detail = detail
        self.actionText = actionText
        self.color = color
        self.accessory = accessory
        self.accessibilityHint = accessibilityHint
    }

    var accessibilityValue: String {
        [text, detail, actionText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct AppUpdateStatusValue: View {
    let presentation: AppUpdateStatusPresentation

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    statusLabel
                    accessory
                }

                VStack(alignment: .trailing, spacing: 4) {
                    statusLabel
                    accessory
                }
            }

            if let detail = presentation.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(presentation.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detail)
            }

            if let actionText = presentation.actionText {
                Text(actionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .multilineTextAlignment(.trailing)
        .padding(.vertical, 2)
    }

    @MainActor
    private var statusLabel: some View {
        HStack(spacing: 8) {
            presentation.icon
                .view(color: presentation.color)

            Text(presentation.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(presentation.color)
    }

    @ViewBuilder
    @MainActor
    private var accessory: some View {
        if let accessory = presentation.accessory {
            accessory.view()
        }
    }
}

private enum AppUpdateStatusIcon {
    case system(String)
    case spinner

    @MainActor
    @ViewBuilder
    func view(color: Color) -> some View {
        switch self {
        case .system(let systemName):
            Image(systemName: systemName)
        case .spinner:
            StatusIndicatorSpinner(
                color: color,
                diameter: 16,
                lineWidth: 2
            )
        }
    }
}

private enum AppUpdateStatusAccessory {
    case progress(Double)

    @MainActor
    @ViewBuilder
    func view() -> some View {
        switch self {
        case .progress(let progress):
            AppUpdateDownloadProgressAccessory(progress: progress)
        }
    }
}

private struct AppUpdateStatusRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background {
                if configuration.isPressed && isEnabled {
                    Color.primary.opacity(SettingsScreenLayout.settingsRowPressedOpacity)
                }
            }
    }
}

private extension AppUpdateUnavailableReason {
    var settingsDescription: String {
        switch self {
        case .gitHubCLINotInstalled:
            return "Install the GitHub CLI to check for Alveary updates."
        case .gitHubCLINotAuthenticated:
            return "Sign in to GitHub CLI to check private Alveary releases."
        case .noRelease:
            return "No GitHub release is available."
        case .privateOrNotFound:
            return "GitHub CLI cannot access the Alveary repository."
        case .draftRelease:
            return "The latest GitHub release is still a draft."
        case .prerelease:
            return "The latest GitHub release is marked as a prerelease."
        case .missingAsset(let expectedName):
            return "The latest release is missing \(expectedName)."
        case .missingAssetDigest(let expectedName):
            return "The latest release is missing a SHA-256 digest for \(expectedName)."
        case .malformedVersion(let version):
            return "The release version could not be read: \(version)."
        case .invalidReleaseURL:
            return "The release URL from GitHub is invalid."
        case .invalidAssetURL:
            return "The release download URL from GitHub is invalid."
        case .invalidAssetDigest:
            return "The release asset SHA-256 digest from GitHub is invalid."
        case .requestFailed(let statusCode):
            return "GitHub returned HTTP \(statusCode)."
        case .rateLimited(let resetDate):
            if let resetDate {
                return "GitHub rate limited update checks until \(resetDate.formatted(date: .abbreviated, time: .shortened))."
            }
            return "GitHub rate limited update checks."
        case .decodingFailed(let message):
            return "The GitHub release response could not be decoded: \(message)"
        case .transportFailed(let message):
            return "The update check failed: \(message)"
        }
    }
}
