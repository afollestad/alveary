import SwiftUI

struct DiffViewerPaneHeader: View {
    let activeDirectory: String?
    let mode: DiffViewerMode
    let contextualAction: DiffViewerViewModel.ContextualAction
    let selectedFiles: [FileStatus]
    let areAgentActionsEnabled: Bool
    let showsFileListDivider: Bool
    let showsFileActions: Bool
    let onModeSelected: (DiffViewerMode) -> Void
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void
    let onViewPRRequested: (String) -> Void
    let onStageSelectedFiles: () -> Void
    let onUnstageSelectedFiles: () -> Void
    let onDiscardSelectedFiles: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            modeMenu

            DiffViewerHeaderActionContainer(actions: headerActions)
        }
        .animation(diffViewerHeaderActionAnimation, value: headerActionLayoutID)
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(showsFileListDivider ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: showsFileListDivider)
                .allowsHitTesting(false)
        }
    }

    private var headerActions: [DiffViewerHeaderAction] {
        var actions: [DiffViewerHeaderAction] = []

        switch visibleContextualAction {
        case .commit:
            actions.append(DiffViewerHeaderAction(
                id: "commit",
                title: "Commit",
                systemImage: "checkmark.circle",
                tone: .primary,
                isEnabled: areAgentActionsEnabled,
                action: onCommitRequested
            ))
        case .openPR:
            actions.append(DiffViewerHeaderAction(
                id: "open-pr",
                title: "Create PR",
                systemImage: "arrow.triangle.branch",
                tone: .primary,
                isEnabled: areAgentActionsEnabled,
                action: onOpenPRRequested
            ))
        case .viewPR(let url):
            actions.append(DiffViewerHeaderAction(
                id: "view-pr",
                title: "View PR",
                systemImage: "arrow.up.right.square",
                tone: .primary,
                isEnabled: true,
                action: { onViewPRRequested(url) }
            ))
        case .none:
            break
        }

        if showsFileActions && hasUnstagedSelection {
            actions.append(DiffViewerHeaderAction(
                id: "stage",
                title: "Stage",
                systemImage: "tray.and.arrow.down",
                tone: .secondary,
                isEnabled: true,
                action: onStageSelectedFiles
            ))
        }

        if showsFileActions && hasStagedSelection {
            actions.append(DiffViewerHeaderAction(
                id: "unstage",
                title: "Unstage",
                systemImage: "tray.and.arrow.up",
                tone: .secondary,
                isEnabled: true,
                action: onUnstageSelectedFiles
            ))
        }

        if showsFileActions && !selectedFiles.isEmpty {
            actions.append(DiffViewerHeaderAction(
                id: "discard",
                title: "Discard",
                systemImage: "arrow.uturn.backward",
                tone: .destructive,
                role: .destructive,
                isEnabled: true,
                action: onDiscardSelectedFiles
            ))
        }

        return actions
    }

    private var visibleContextualAction: DiffViewerViewModel.ContextualAction {
        guard mode == .commits else {
            return contextualAction
        }

        switch contextualAction {
        case .openPR, .viewPR:
            return contextualAction
        case .commit, .none:
            return .none
        }
    }

    private var headerActionLayoutID: String {
        headerActions.map { "\($0.id):\($0.isEnabled)" }.joined(separator: "|")
    }

    private var modeMenu: some View {
        Menu {
            ForEach(DiffViewerMode.allCases, id: \.self) { mode in
                Button(mode.title) {
                    onModeSelected(mode)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(mode.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(
                maxWidth: .infinity,
                minHeight: diffViewerHeaderControlHeight,
                maxHeight: diffViewerHeaderControlHeight,
                alignment: .leading
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(DiffViewerModeMenuButtonStyle())
        .accessibilityLabel("Diff viewer mode")
        .accessibilityValue("\(mode.title), \(displayDirectory)")
    }

    private var displayDirectory: String {
        guard let activeDirectory else {
            return "No project selected"
        }

        return CanonicalPath.abbreviateHomeDirectory(activeDirectory)
    }

    private var hasStagedSelection: Bool {
        selectedFiles.contains(where: \.isStaged)
    }

    private var hasUnstagedSelection: Bool {
        selectedFiles.contains { !$0.isStaged }
    }
}

private let diffViewerHeaderControlHeight: CGFloat = 36
private let diffViewerHeaderActionSpacing: CGFloat = 6
private let diffViewerHeaderActionAnimation = Animation.easeInOut(duration: 0.18)

private struct DiffViewerHeaderAction {
    let id: String
    let title: String
    let systemImage: String
    let tone: DiffViewerHeaderIconButtonStyle.Tone
    var role: ButtonRole?
    let isEnabled: Bool
    let action: () -> Void
}

private struct DiffViewerModeMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.06) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.14), lineWidth: 1)
            )
    }
}

private struct DiffViewerHeaderActionContainer: View {
    let actions: [DiffViewerHeaderAction]

    var body: some View {
        HStack(spacing: diffViewerHeaderActionSpacing) {
            ForEach(actions, id: \.id) { action in
                Button(role: action.role, action: action.action) {
                    Image(systemName: action.systemImage)
                }
                .buttonStyle(DiffViewerHeaderIconButtonStyle(tone: action.tone))
                .help(action.title)
                .accessibilityLabel(action.title)
                .disabled(!action.isEnabled)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.leading, actions.isEmpty ? 0 : diffViewerHeaderActionSpacing)
        .frame(width: reservedWidth, alignment: .trailing)
        .clipped()
        .animation(diffViewerHeaderActionAnimation, value: layoutID)
    }

    private var reservedWidth: CGFloat {
        guard !actions.isEmpty else {
            return 0
        }

        return CGFloat(actions.count) * diffViewerHeaderControlHeight
            + CGFloat(actions.count) * diffViewerHeaderActionSpacing
    }

    private var layoutID: String {
        actions.map { "\($0.id):\($0.isEnabled)" }.joined(separator: "|")
    }
}

private struct DiffViewerHeaderIconButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case destructive
    }

    let tone: Tone

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor.opacity(isEnabled ? 1 : 0.55))
            .frame(width: diffViewerHeaderControlHeight, height: diffViewerHeaderControlHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed).opacity(isEnabled ? 1 : 0.38))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor.opacity(borderOpacity), lineWidth: borderWidth)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary, .secondary:
            return .primary
        case .destructive:
            return .white
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            return AppAccentFill.primary
        case .secondary:
            return .primary
        case .destructive:
            return destructiveColor
        }
    }

    private var borderOpacity: Double {
        tone == .secondary ? 0.14 : 0
    }

    private var borderWidth: CGFloat {
        tone == .secondary ? 1 : 0
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let baseColor: Color = switch tone {
        case .primary:
            AppAccentFill.primary
        case .secondary:
            Color(nsColor: .windowBackgroundColor)
        case .destructive:
            destructiveColor
        }

        return isPressed ? baseColor.opacity(0.84) : baseColor
    }

    private var destructiveColor: Color {
        Color(red: 0.74, green: 0.18, blue: 0.17)
    }
}
