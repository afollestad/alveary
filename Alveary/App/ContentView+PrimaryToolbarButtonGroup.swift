import SwiftUI
import SwiftData

struct PrimaryToolbarButtonGroup: View {
    let selectedThreadID: PersistentIdentifier?
    let projectActions: [AlvearyProjectConfig.ProjectAction]
    let projectActionsThreadID: PersistentIdentifier?
    let terminalTitle: String
    let terminalDisplayState: TerminalToolbarDisplayState
    let terminalHelpText: String
    /// Nil hides the pull-request button entirely — no thread selected, or the
    /// integration is off.
    let pullRequestState: PullRequestLinksToolbarState?
    let pullRequestHelpText: String
    let isPullRequestPopoverPresented: Binding<Bool>
    let diffDisplayState: DiffViewerToolbarDisplayState
    let diffHelpText: String
    let diffAccessibilityLabel: String
    let diffAccessibilityValue: String
    let settingsBadgeState: AppUpdateToolbarBadgeState
    let onProjectAction: (PersistentIdentifier, AlvearyProjectConfig.ProjectAction) -> Void
    let onToggleTerminal: () -> Void
    let onPullRequestAction: () -> Void
    let onPullRequestSecondaryAction: () -> Void
    let pullRequestPopoverContent: () -> AnyView
    let onToggleDiffViewer: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProjectActionsSlotWidth: CGFloat
    @State private var areProjectActionsVisible: Bool
    @State private var animatedPullRequestSlotWidth: CGFloat
    @State private var isPullRequestButtonVisible: Bool

    init(
        selectedThreadID: PersistentIdentifier?,
        projectActions: [AlvearyProjectConfig.ProjectAction],
        projectActionsThreadID: PersistentIdentifier?,
        terminalTitle: String,
        terminalDisplayState: TerminalToolbarDisplayState,
        terminalHelpText: String,
        pullRequestState: PullRequestLinksToolbarState?,
        pullRequestHelpText: String,
        isPullRequestPopoverPresented: Binding<Bool>,
        diffDisplayState: DiffViewerToolbarDisplayState,
        diffHelpText: String,
        diffAccessibilityLabel: String,
        diffAccessibilityValue: String,
        settingsBadgeState: AppUpdateToolbarBadgeState = .none,
        onProjectAction: @escaping (PersistentIdentifier, AlvearyProjectConfig.ProjectAction) -> Void,
        onToggleTerminal: @escaping () -> Void,
        onPullRequestAction: @escaping () -> Void,
        onPullRequestSecondaryAction: @escaping () -> Void,
        pullRequestPopoverContent: @escaping () -> AnyView,
        onToggleDiffViewer: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.selectedThreadID = selectedThreadID
        self.projectActions = projectActions
        self.projectActionsThreadID = projectActionsThreadID
        self.terminalTitle = terminalTitle
        self.terminalDisplayState = terminalDisplayState
        self.terminalHelpText = terminalHelpText
        self.pullRequestState = pullRequestState
        self.pullRequestHelpText = pullRequestHelpText
        self.isPullRequestPopoverPresented = isPullRequestPopoverPresented
        self.diffDisplayState = diffDisplayState
        self.diffHelpText = diffHelpText
        self.diffAccessibilityLabel = diffAccessibilityLabel
        self.diffAccessibilityValue = diffAccessibilityValue
        self.settingsBadgeState = settingsBadgeState
        self.onProjectAction = onProjectAction
        self.onToggleTerminal = onToggleTerminal
        self.onPullRequestAction = onPullRequestAction
        self.onPullRequestSecondaryAction = onPullRequestSecondaryAction
        self.pullRequestPopoverContent = pullRequestPopoverContent
        self.onToggleDiffViewer = onToggleDiffViewer
        self.onOpenSettings = onOpenSettings

        let initialProjectActionsSlotWidth = PrimaryToolbarGroupWidth.projectActionsSlotWidth(
            actionCount: Self.projectActionButtonCount(
                selectedThreadID: selectedThreadID,
                projectActions: projectActions,
                projectActionsThreadID: projectActionsThreadID
            )
        )
        _animatedProjectActionsSlotWidth = State(initialValue: initialProjectActionsSlotWidth)
        _areProjectActionsVisible = State(initialValue: initialProjectActionsSlotWidth > 0)
        let initialPullRequestSlotWidth = PrimaryToolbarGroupWidth.pullRequestSlotWidth(
            isVisible: pullRequestState != nil
        )
        _animatedPullRequestSlotWidth = State(initialValue: initialPullRequestSlotWidth)
        _isPullRequestButtonVisible = State(initialValue: pullRequestState != nil)
    }

    var body: some View {
        toolbarContent
            // Reserve the target width immediately for AppKit; only the
            // trailing-aligned visible capsule animates, so the right edge is fixed.
            .frame(width: targetToolbarGroupWidth, alignment: .trailing)
            .onChange(of: projectActionButtonCount) { _, _ in
                updateProjectActionsPresentation()
            }
            .onChange(of: pullRequestState != nil) { _, _ in
                updatePullRequestPresentation()
            }
    }

    private var toolbarContent: some View {
        // Keep these controls in one SwiftUI-owned toolbar item so the visible
        // capsule follows the animated action and diff slots on the same layout pass.
        HStack(spacing: 0) {
            PrimaryToolbarProjectActionsSlot(
                selectedThreadID: selectedThreadID,
                projectActions: projectActions,
                projectActionsThreadID: projectActionsThreadID,
                width: animatedProjectActionsSlotWidth,
                areActionsVisible: areProjectActionsVisible,
                onProjectAction: onProjectAction
            )

            coreToolbarButtons
        }
        .padding(.horizontal, PrimaryToolbarMetrics.containerHorizontalInset)
        .padding(.vertical, PrimaryToolbarMetrics.containerVerticalInset)
        .background(PrimaryToolbarContainerBackground(colorScheme: colorScheme))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var coreToolbarButtons: some View {
        HStack(spacing: PrimaryToolbarMetrics.buttonSpacing) {
            TerminalToolbarButton(
                title: terminalTitle,
                displayState: terminalDisplayState,
                action: onToggleTerminal
            )
            .primaryToolbarIconButtonStyle()
            .help(terminalHelpText)
            .accessibilityLabel(terminalTitle)

            PrimaryToolbarPullRequestSlot(
                state: pullRequestState,
                helpText: pullRequestHelpText,
                width: animatedPullRequestSlotWidth,
                isButtonVisible: isPullRequestButtonVisible,
                isPopoverPresented: isPullRequestPopoverPresented,
                onAction: onPullRequestAction,
                onSecondaryAction: onPullRequestSecondaryAction,
                popoverContent: pullRequestPopoverContent
            )

            DiffViewerToolbarButton(
                displayState: diffDisplayState,
                action: onToggleDiffViewer
            )
            .primaryToolbarIconButtonStyle(selector: .fullCapsule)
            .help(diffHelpText)
            .accessibilityLabel(diffAccessibilityLabel)
            .accessibilityValue(diffAccessibilityValue)

            PrimaryToolbarSettingsButton(
                badgeState: settingsBadgeState,
                action: onOpenSettings
            )
        }
    }

    private var targetToolbarGroupWidth: CGFloat {
        PrimaryToolbarGroupWidth.groupWidth(
            projectActionsSlotWidth: targetProjectActionsSlotWidth,
            pullRequestSlotWidth: targetPullRequestSlotWidth,
            diffStatusWidth: diffDisplayState.statusSlotWidth
        )
    }

    private var targetProjectActionsSlotWidth: CGFloat {
        PrimaryToolbarGroupWidth.projectActionsSlotWidth(actionCount: projectActionButtonCount)
    }

    private var targetPullRequestSlotWidth: CGFloat {
        PrimaryToolbarGroupWidth.pullRequestSlotWidth(isVisible: pullRequestState != nil)
    }

    private func updatePullRequestPresentation() {
        withAnimation(PrimaryToolbarMetrics.statusAnimation) {
            animatedPullRequestSlotWidth = targetPullRequestSlotWidth
            isPullRequestButtonVisible = pullRequestState != nil
        }
    }

    private var projectActionButtonCount: Int {
        Self.projectActionButtonCount(
            selectedThreadID: selectedThreadID,
            projectActions: projectActions,
            projectActionsThreadID: projectActionsThreadID
        )
    }

    private func updateProjectActionsPresentation() {
        withAnimation(PrimaryToolbarMetrics.statusAnimation) {
            animatedProjectActionsSlotWidth = targetProjectActionsSlotWidth
            areProjectActionsVisible = targetProjectActionsSlotWidth > 0
        }
    }

    // While a thread switch's action refresh is in flight, the previously
    // loaded actions stay rendered (their buttons keep targeting the thread
    // they were loaded for) so same-project switches do not collapse and
    // re-expand the slot on every selection change.
    private static func projectActionButtonCount(
        selectedThreadID: PersistentIdentifier?,
        projectActions: [AlvearyProjectConfig.ProjectAction],
        projectActionsThreadID: PersistentIdentifier?
    ) -> Int {
        guard selectedThreadID != nil, projectActionsThreadID != nil else {
            return 0
        }
        return projectActions.count
    }
}

enum PrimaryToolbarGroupWidth {
    static func projectActionStripWidth(actionCount: Int) -> CGFloat {
        guard actionCount > 0 else {
            return 0
        }

        return CGFloat(actionCount) * PrimaryToolbarMetrics.iconButtonSize
            + CGFloat(actionCount - 1) * PrimaryToolbarMetrics.buttonSpacing
    }

    static func projectActionsSlotWidth(actionCount: Int) -> CGFloat {
        guard actionCount > 0 else {
            return 0
        }

        return projectActionStripWidth(actionCount: actionCount)
            + PrimaryToolbarMetrics.buttonSpacing
    }

    /// The pull-request button is conditional, so it rides an animated slot like
    /// the project actions rather than the fixed core-button count.
    static func pullRequestSlotWidth(isVisible: Bool) -> CGFloat {
        guard isVisible else {
            return 0
        }
        return PrimaryToolbarMetrics.iconButtonSize + PrimaryToolbarMetrics.buttonSpacing
    }

    static func groupWidth(
        projectActionsSlotWidth: CGFloat,
        pullRequestSlotWidth: CGFloat,
        diffStatusWidth: CGFloat
    ) -> CGFloat {
        PrimaryToolbarMetrics.containerHorizontalInset * 2
            + coreToolbarButtonWidth
            + coreToolbarSpacingWidth
            + projectActionsSlotWidth
            + pullRequestSlotWidth
            + diffStatusWidth
    }

    private static let coreToolbarButtonCount: CGFloat = 3
    private static let coreToolbarButtonWidth = coreToolbarButtonCount * PrimaryToolbarMetrics.iconButtonSize
    private static let coreToolbarSpacingWidth = (coreToolbarButtonCount - 1) * PrimaryToolbarMetrics.buttonSpacing
}

enum PrimaryToolbarMetrics {
    static let buttonSpacing: CGFloat = 4
    static let containerHorizontalInset: CGFloat = 8
    static let containerVerticalInset: CGFloat = 4
    static let containerBorderWidth: CGFloat = 1
    static let iconButtonSize: CGFloat = 30
    static let iconFont = Font.system(size: 16, weight: .medium)
    /// Octicons are fixed 24pt artwork rather than font-sized symbols, so they
    /// need an explicit glyph box that optically matches `iconFont` in this row.
    static let octiconSize: CGFloat = 16
    static let statusFont = Font.body.weight(.medium)
    static let statusSpacing: CGFloat = 2
    static let diffSummarySpacing: CGFloat = 6
    static let diffSummaryTrailingPadding: CGFloat = 4
    static let progressIndicatorSize: CGFloat = 16
    static let badgeDiameter: CGFloat = 8
    static let statusAnimation = Animation.spring(response: 0.24, dampingFraction: 0.9)
    static let interactionAnimation = Animation.easeOut(duration: 0.12)
}

private struct PrimaryToolbarProjectActionsSlot: View {
    let selectedThreadID: PersistentIdentifier?
    let projectActions: [AlvearyProjectConfig.ProjectAction]
    let projectActionsThreadID: PersistentIdentifier?
    let width: CGFloat
    let areActionsVisible: Bool
    let onProjectAction: (PersistentIdentifier, AlvearyProjectConfig.ProjectAction) -> Void

    var body: some View {
        // Project actions are an animated leading slot so inserting toolbar
        // children cannot fight the diff button's own width animation.
        HStack(spacing: PrimaryToolbarMetrics.buttonSpacing) {
            projectActionButtons
        }
        .padding(.trailing, slotTrailingPadding)
        // Reveal leftward from the terminal button, clipping content until the
        // shared capsule has enough width for the action buttons.
        .frame(width: width, alignment: .trailing)
        .clipped()
        .opacity(areActionsVisible ? 1 : 0)
        .scaleEffect(areActionsVisible ? 1 : 0.92, anchor: .trailing)
        .animation(PrimaryToolbarMetrics.statusAnimation, value: areActionsVisible)
    }

    @ViewBuilder
    private var projectActionButtons: some View {
        // Buttons act on the thread their actions were loaded for, so actions
        // rendered while a newer thread's refresh resolves cannot run another
        // project's command against the newly selected thread.
        if selectedThreadID != nil,
           let projectActionsThreadID,
           !projectActions.isEmpty {
            ForEach(Array(projectActions.enumerated()), id: \.offset) { _, action in
                Button {
                    onProjectAction(projectActionsThreadID, action)
                } label: {
                    Label(action.name, systemImage: action.icon ?? "terminal")
                        .labelStyle(.iconOnly)
                }
                .primaryToolbarIconButtonStyle()
                .help(action.name)
            }
        }
    }

    private var slotTrailingPadding: CGFloat {
        projectActions.isEmpty || selectedThreadID == nil || projectActionsThreadID == nil
            ? 0
            : PrimaryToolbarMetrics.buttonSpacing
    }
}

/// The pull-request button's animated slot. It mounts only for a selected thread
/// with the integration enabled, so like the project actions it reveals through a
/// width animation instead of appearing as a raw conditional sibling — otherwise
/// its insertion fights the diff button's own width animation.
private struct PrimaryToolbarPullRequestSlot: View {
    let state: PullRequestLinksToolbarState?
    let helpText: String
    let width: CGFloat
    let isButtonVisible: Bool
    let isPopoverPresented: Binding<Bool>
    let onAction: () -> Void
    let onSecondaryAction: () -> Void
    let popoverContent: () -> AnyView

    var body: some View {
        slotContent
            // `width` is the group-width *reserve*: button plus the extra HStack
            // spacing its presence adds. The rendered frame is the button alone —
            // the parent HStack already spaces both sides, so folding the spacing
            // into the frame would double the trailing gap and read as an uneven
            // inset. When the button is absent the empty content collapses out of
            // layout entirely, taking its HStack spacing with it.
            .frame(
                width: max(width - PrimaryToolbarMetrics.buttonSpacing, 0),
                alignment: .trailing
            )
            .clipped()
            .opacity(isButtonVisible ? 1 : 0)
            .scaleEffect(isButtonVisible ? 1 : 0.92, anchor: .trailing)
            .animation(PrimaryToolbarMetrics.statusAnimation, value: isButtonVisible)
    }

    @ViewBuilder
    private var slotContent: some View {
        if let state {
            PullRequestToolbarButton(state: state, action: onAction)
                .primaryToolbarIconButtonStyle()
                .help(helpText)
                .accessibilityLabel(state.accessibilityLabel)
                .accessibilityValue(state.accessibilityValue)
                // Secondary click always opens the popover, even when a left
                // click would open the pane, so another link can be added.
                .overlay {
                    SecondaryClickTarget(onSecondaryClick: onSecondaryAction)
                }
                // An AppKit popover, not SwiftUI's: only a popover whose window
                // we own can become `NSApp.keyWindow`, which is what lets the
                // URL field receive ⌘V. See `AppKitAnchoredPopover`.
                .appKitPopover(isPresented: isPopoverPresented, preferredEdge: .maxY) {
                    popoverContent()
                }
        }
    }
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
        StatusIndicatorSpinner(
            color: .secondary,
            diameter: PrimaryToolbarMetrics.progressIndicatorSize,
            lineWidth: 2
        )
        .frame(
            width: PrimaryToolbarMetrics.iconButtonSize,
            height: PrimaryToolbarMetrics.iconButtonSize
        )
    }
}
