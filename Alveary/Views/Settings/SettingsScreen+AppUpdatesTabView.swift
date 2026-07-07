import SwiftUI

struct AppUpdatesSettingsTabView: View {
    let updateManager: AppUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection("Update check") {
                AppUpdateInfoRow(
                    title: "Current version",
                    value: currentVersionText
                )

                AppUpdateInfoRow(
                    title: "Latest version",
                    value: latestVersionText
                )

                AppUpdateStatusRow(presentation: statusPresentation)

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

    var statusPresentation: AppUpdateStatusPresentation {
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
                color: .blue
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

    var body: some View {
        SettingsFormRow {
            HStack(spacing: 16) {
                Text("Status")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 24)

                Label {
                    Text(presentation.text)
                } icon: {
                    presentation.icon
                        .view(color: presentation.color)
                }
                .foregroundStyle(presentation.color)
                .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct AppUpdateStatusPresentation {
    let icon: AppUpdateStatusIcon
    let text: String
    let color: Color
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
        case .malformedVersion(let version):
            return "The release version could not be read: \(version)."
        case .invalidReleaseURL:
            return "The release URL from GitHub is invalid."
        case .invalidAssetURL:
            return "The release download URL from GitHub is invalid."
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
