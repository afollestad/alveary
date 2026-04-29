import SwiftUI

struct PrimaryToolbarButtonGroup: View {
    let selectedThread: AgentThread?
    let projectActions: [AlvearyProjectConfig.ProjectAction]
    let terminalTitle: String
    let terminalDisplayState: TerminalToolbarDisplayState
    let terminalHelpText: String
    let diffDisplayState: DiffViewerToolbarDisplayState
    let diffHelpText: String
    let diffAccessibilityLabel: String
    let diffAccessibilityValue: String
    let onProjectAction: (AgentThread, AlvearyProjectConfig.ProjectAction) -> Void
    let onToggleTerminal: () -> Void
    let onToggleDiffViewer: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        toolbarContent
            // Give AppKit the destination width while the visible capsule animates
            // inside it from the trailing edge; the final position must not carry
            // any persistent offset.
            .frame(width: toolbarGroupWidth, alignment: .trailing)
    }

    private var toolbarContent: some View {
        // Keep these controls in one SwiftUI-owned toolbar item so the group's
        // width follows the diff status slot's animated width on the same layout pass.
        HStack(spacing: PrimaryToolbarMetrics.buttonSpacing) {
            projectActionButtons

            TerminalToolbarButton(
                title: terminalTitle,
                displayState: terminalDisplayState,
                action: onToggleTerminal
            )
            .primaryToolbarIconButtonStyle()
            .help(terminalHelpText)
            .accessibilityLabel(terminalTitle)

            DiffViewerToolbarButton(
                displayState: diffDisplayState,
                action: onToggleDiffViewer
            )
            .primaryToolbarIconButtonStyle(selector: .fullCapsule)
            .help(diffHelpText)
            .accessibilityLabel(diffAccessibilityLabel)
            .accessibilityValue(diffAccessibilityValue)

            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .primaryToolbarIconButtonStyle()
            .help("Open Settings (\(KeyboardShortcut.settings.displayString))")
        }
        .padding(.horizontal, PrimaryToolbarMetrics.containerHorizontalInset)
        .padding(.vertical, PrimaryToolbarMetrics.containerVerticalInset)
        .background(PrimaryToolbarContainerBackground(colorScheme: colorScheme))
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var projectActionButtons: some View {
        if let selectedThread, !projectActions.isEmpty {
            ForEach(Array(projectActions.enumerated()), id: \.offset) { _, action in
                Button {
                    onProjectAction(selectedThread, action)
                } label: {
                    Label(action.name, systemImage: action.icon ?? "terminal")
                        .labelStyle(.iconOnly)
                }
                .primaryToolbarIconButtonStyle()
                .help(action.name)
            }
        }
    }

    private var toolbarGroupWidth: CGFloat {
        let buttonCount = projectActionButtonCount + 3
        let interButtonSpacing = CGFloat(max(buttonCount - 1, 0)) * PrimaryToolbarMetrics.buttonSpacing
        return PrimaryToolbarMetrics.containerHorizontalInset * 2
            + CGFloat(buttonCount) * PrimaryToolbarMetrics.iconButtonSize
            + interButtonSpacing
            + diffDisplayState.statusSlotWidth
    }

    private var projectActionButtonCount: Int {
        selectedThread == nil ? 0 : projectActions.count
    }
}

enum PrimaryToolbarMetrics {
    static let buttonSpacing: CGFloat = 4
    static let containerHorizontalInset: CGFloat = 8
    static let containerVerticalInset: CGFloat = 4
    static let containerBorderWidth: CGFloat = 1
    static let iconButtonSize: CGFloat = 30
    static let iconFont = Font.system(size: 16, weight: .medium)
    static let statusFont = Font.body.weight(.medium)
    static let statusSpacing: CGFloat = 6
    static let diffSummarySpacing: CGFloat = 6
    static let diffSummaryTrailingPadding: CGFloat = 4
    static let progressIndicatorSize: CGFloat = 16
    static let progressScale: CGFloat = 0.95
    static let statusAnimation = Animation.spring(response: 0.24, dampingFraction: 0.9)
    static let interactionAnimation = Animation.easeOut(duration: 0.12)
}

private struct PrimaryToolbarContainerBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        // AppKit's shared toolbar background is hidden so it cannot wrap the
        // whole group as one large control; this recreates native-like control
        // chrome in the SwiftUI-owned bounds.
        Capsule(style: .continuous)
            .fill(containerFill)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(containerBorder, lineWidth: PrimaryToolbarMetrics.containerBorderWidth)
            }
    }

    private var containerFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.025)
            : Color.black.opacity(0.08)
    }

    private var containerBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.10)
    }
}

struct PrimaryToolbarProgressSlot: View {
    var body: some View {
        // Progress-only toolbar states occupy the same footprint as icon buttons,
        // so loading states do not change hit target or visual alignment.
        ProgressView()
            .controlSize(.small)
            .tint(.blue)
            .scaleEffect(PrimaryToolbarMetrics.progressScale)
            .frame(
                width: PrimaryToolbarMetrics.progressIndicatorSize,
                height: PrimaryToolbarMetrics.progressIndicatorSize
            )
            .frame(
                width: PrimaryToolbarMetrics.iconButtonSize,
                height: PrimaryToolbarMetrics.iconButtonSize
            )
    }
}

extension View {
    func primaryToolbarIconButtonStyle(selector: PrimaryToolbarSelectorShape = .iconCircle) -> some View {
        buttonStyle(PrimaryToolbarIconButtonStyle(selector: selector))
    }
}

enum PrimaryToolbarSelectorShape {
    case iconCircle
    case fullCapsule
}

private struct PrimaryToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let selector: PrimaryToolbarSelectorShape

    func makeBody(configuration: Configuration) -> some View {
        PrimaryToolbarIconButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            selector: selector
        )
    }
}

private struct PrimaryToolbarIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let selector: PrimaryToolbarSelectorShape

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(PrimaryToolbarMetrics.iconFont)
            .imageScale(.medium)
            .foregroundStyle(.primary.opacity(foregroundOpacity))
            .frame(
                minWidth: PrimaryToolbarMetrics.iconButtonSize,
                minHeight: PrimaryToolbarMetrics.iconButtonSize
            )
            .contentShape(Rectangle())
            .background(alignment: .leading) {
                selectorBackground
            }
            .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(PrimaryToolbarMetrics.interactionAnimation, value: isHovering)
            .animation(PrimaryToolbarMetrics.interactionAnimation, value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var foregroundOpacity: Double {
        guard isEnabled else {
            return 0.45
        }

        return isHovering ? 0.95 : 0.82
    }

    @ViewBuilder
    private var selectorBackground: some View {
        switch selector {
        case .iconCircle:
            Circle()
                .fill(selectorFill)
                .frame(
                    width: PrimaryToolbarMetrics.iconButtonSize,
                    height: PrimaryToolbarMetrics.iconButtonSize
                )
        case .fullCapsule:
            // The diff button grows to show stats; its selector should cover
            // that full interactive label, not only the leading icon.
            Capsule(style: .continuous)
                .fill(selectorFill)
        }
    }

    private var selectorFill: Color {
        Color.primary.opacity(isHovering && isEnabled ? 0.1 : 0)
    }
}
