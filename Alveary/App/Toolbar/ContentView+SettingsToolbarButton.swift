import SwiftUI

enum AppUpdateToolbarBadgeState: Equatable, Sendable {
    case none
    case updateAvailable
    case readyToInstall

    init(updateAvailable: Bool, readyToInstall: Bool) {
        if readyToInstall {
            self = .readyToInstall
        } else if updateAvailable {
            self = .updateAvailable
        } else {
            self = .none
        }
    }
}

extension AppUpdateToolbarBadgeState {
    var settingsTargetPage: AppSettings.SettingsPage? {
        switch self {
        case .none:
            return nil
        case .updateAvailable,
             .readyToInstall:
            return .appUpdates
        }
    }

    var accessibilityValue: String {
        switch self {
        case .none:
            return "No app update available"
        case .updateAvailable:
            return "App update available"
        case .readyToInstall:
            return "App update ready to install"
        }
    }
}

extension AppUpdateManager {
    var toolbarBadgeState: AppUpdateToolbarBadgeState {
        let updateAvailable: Bool
        if case .updateAvailable = status {
            updateAvailable = true
        } else {
            updateAvailable = false
        }

        return AppUpdateToolbarBadgeState(
            updateAvailable: updateAvailable,
            readyToInstall: stagedUpdate != nil
        )
    }
}

struct PrimaryToolbarSettingsButton: View {
    let badgeState: AppUpdateToolbarBadgeState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(
                        width: PrimaryToolbarMetrics.iconButtonSize,
                        height: PrimaryToolbarMetrics.iconButtonSize
                    )

                badge
                    .padding(.top, 5)
                    .padding(.trailing, 5)
            }
            .frame(
                width: PrimaryToolbarMetrics.iconButtonSize,
                height: PrimaryToolbarMetrics.iconButtonSize
            )
        }
        .primaryToolbarIconButtonStyle()
        .help(helpText)
        .accessibilityLabel("Settings")
        .accessibilityValue(badgeState.accessibilityValue)
    }

    @ViewBuilder
    private var badge: some View {
        if let color = badgeState.badgeColor {
            Circle()
                .fill(color)
                .frame(
                    width: PrimaryToolbarMetrics.badgeDiameter,
                    height: PrimaryToolbarMetrics.badgeDiameter
                )
                .overlay {
                    Circle()
                        .strokeBorder(Self.badgeRingColor, lineWidth: 1)
                }
        }
    }

    /// The ring separating the badge from the gear glyph under it. Deliberately not
    /// `.background`, which resolves white in light mode and reads as a halo around the
    /// dot rather than a cut-out. This fixed tone matches dark mode's window background,
    /// so adopting it changed light mode only.
    private static let badgeRingColor = Color(white: 0.12)

    private var helpText: String {
        if let badgeHelpText = badgeState.helpText {
            return "\(badgeHelpText) (\(KeyboardShortcut.settings.displayString))"
        }

        return "Open Settings (\(KeyboardShortcut.settings.displayString))"
    }
}

private extension AppUpdateToolbarBadgeState {
    var badgeColor: Color? {
        switch self {
        case .none:
            return nil
        case .updateAvailable:
            // Not a status dot: blue means "waiting on the user" on the app's dot
            // surfaces (see Status Dot Colors in `Alveary/Views/AGENTS.md`), so the
            // update badge takes accent chrome instead. `.readyToInstall` keeps
            // green, which means the same thing here as it does there.
            return AppAccentIcon.foreground
        case .readyToInstall:
            return .green
        }
    }

    var helpText: String? {
        switch self {
        case .none:
            return nil
        case .updateAvailable:
            return "Open Updates"
        case .readyToInstall:
            return "Open Updates to restart"
        }
    }
}
