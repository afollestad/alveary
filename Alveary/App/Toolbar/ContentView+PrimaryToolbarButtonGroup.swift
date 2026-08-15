import SwiftUI
import SwiftData

struct PrimaryToolbarButtonGroup: View {
    /// Whether the selection is one project actions can belong to at all; the slot
    /// collapses without it even while a previous selection's actions are loaded.
    let isSelectionProjectActionCapable: Bool
    let projectActions: [AlvearyProjectConfig.ProjectAction]
    let projectActionsOwner: ToolbarProjectActionsOwner?
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
    let onProjectAction: (ToolbarProjectActionsOwner, AlvearyProjectConfig.ProjectAction) -> Void
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
        isSelectionProjectActionCapable: Bool,
        projectActions: [AlvearyProjectConfig.ProjectAction],
        projectActionsOwner: ToolbarProjectActionsOwner?,
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
        onProjectAction: @escaping (ToolbarProjectActionsOwner, AlvearyProjectConfig.ProjectAction) -> Void,
        onToggleTerminal: @escaping () -> Void,
        onPullRequestAction: @escaping () -> Void,
        onPullRequestSecondaryAction: @escaping () -> Void,
        pullRequestPopoverContent: @escaping () -> AnyView,
        onToggleDiffViewer: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.isSelectionProjectActionCapable = isSelectionProjectActionCapable
        self.projectActions = projectActions
        self.projectActionsOwner = projectActionsOwner
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
            symbols: Self.projectActionSymbols(
                isSelectionProjectActionCapable: isSelectionProjectActionCapable,
                projectActions: projectActions,
                projectActionsOwner: projectActionsOwner
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
            .onChange(of: projectActionSymbols) { _, _ in
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
                isSelectionProjectActionCapable: isSelectionProjectActionCapable,
                projectActions: projectActions,
                projectActionsOwner: projectActionsOwner,
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

    // Spacing is per-boundary rather than one `HStack(spacing:)`, because the
    // octicon glyphs carry less ink than the SF Symbols beside them — see
    // `PrimaryToolbarOpticalSpacing`.
    private var coreToolbarButtons: some View {
        HStack(spacing: 0) {
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
            .padding(.leading, PrimaryToolbarOpticalSpacing.beforeDiffViewer)

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

            PrimaryToolbarSettingsButton(
                badgeState: settingsBadgeState,
                action: onOpenSettings
            )
            .padding(.leading, PrimaryToolbarOpticalSpacing.beforeSettings)
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
        PrimaryToolbarGroupWidth.projectActionsSlotWidth(symbols: projectActionSymbols)
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

    private var projectActionSymbols: [String] {
        Self.projectActionSymbols(
            isSelectionProjectActionCapable: isSelectionProjectActionCapable,
            projectActions: projectActions,
            projectActionsOwner: projectActionsOwner
        )
    }

    private func updateProjectActionsPresentation() {
        withAnimation(PrimaryToolbarMetrics.statusAnimation) {
            animatedProjectActionsSlotWidth = targetProjectActionsSlotWidth
            areProjectActionsVisible = targetProjectActionsSlotWidth > 0
        }
    }

    // While a selection switch's action refresh is in flight, the previously
    // loaded actions stay rendered (their buttons keep targeting the owner they
    // were loaded for) so same-project switches do not collapse and re-expand the
    // slot on every selection change.
    //
    // Symbols rather than a count: the strip's spacing is derived from glyph ink,
    // so both the reserved width and the rendered padding need the names. The
    // fallback matches `projectActionButtons`.
    static func projectActionSymbols(
        isSelectionProjectActionCapable: Bool,
        projectActions: [AlvearyProjectConfig.ProjectAction],
        projectActionsOwner: ToolbarProjectActionsOwner?
    ) -> [String] {
        guard isSelectionProjectActionCapable, projectActionsOwner != nil else {
            return []
        }
        return projectActions.map { $0.icon ?? defaultProjectActionSymbol }
    }

    static let defaultProjectActionSymbol = "terminal"
}

private struct PrimaryToolbarProjectActionsSlot: View {
    let isSelectionProjectActionCapable: Bool
    let projectActions: [AlvearyProjectConfig.ProjectAction]
    let projectActionsOwner: ToolbarProjectActionsOwner?
    let width: CGFloat
    let areActionsVisible: Bool
    let onProjectAction: (ToolbarProjectActionsOwner, AlvearyProjectConfig.ProjectAction) -> Void

    var body: some View {
        // Project actions are an animated leading slot so inserting toolbar
        // children cannot fight the diff button's own width animation. Spacing is
        // per-boundary, derived from each pair's glyph ink, so it must stay in
        // step with `PrimaryToolbarGroupWidth.projectActionsSlotWidth`.
        HStack(spacing: 0) {
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
        // Buttons act on the owner their actions were loaded for, so actions
        // rendered while a newer selection's refresh resolves cannot run another
        // project's command against the newly selected thread or project.
        if isSelectionProjectActionCapable,
           let projectActionsOwner,
           !projectActions.isEmpty {
            ForEach(Array(projectActions.enumerated()), id: \.offset) { index, action in
                Button {
                    onProjectAction(projectActionsOwner, action)
                } label: {
                    Label(
                        action.name,
                        systemImage: action.icon ?? PrimaryToolbarButtonGroup.defaultProjectActionSymbol
                    )
                    .labelStyle(.iconOnly)
                }
                .primaryToolbarIconButtonStyle()
                .help(action.name)
                .padding(.leading, leadingSpacing(before: index))
            }
        }
    }

    /// Zero for the first button — the slot's own frame supplies that edge.
    private func leadingSpacing(before index: Int) -> CGFloat {
        guard index > 0, index < symbols.count else {
            return 0
        }
        return PrimaryToolbarGlyphInk.spacing(after: symbols[index - 1], before: symbols[index])
    }

    private var slotTrailingPadding: CGFloat {
        guard let last = symbols.last else {
            return 0
        }
        return PrimaryToolbarGlyphInk.spacing(
            after: PrimaryToolbarGlyphInk.width(ofSymbol: last),
            before: PrimaryToolbarGlyphInk.terminalInk
        )
    }

    private var symbols: [String] {
        PrimaryToolbarButtonGroup.projectActionSymbols(
            isSelectionProjectActionCapable: isSelectionProjectActionCapable,
            projectActions: projectActions,
            projectActionsOwner: projectActionsOwner
        )
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
            // The row spaces per boundary rather than uniformly, so this slot owns
            // the leading spacing its presence adds and `width` reserves both. The
            // padding sits inside the animated frame so a collapse takes the
            // spacing with it; the settings button supplies the trailing side
            // either way.
            .padding(.leading, PrimaryToolbarOpticalSpacing.beforePullRequest)
            .frame(width: width, alignment: .trailing)
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
                    SecondaryClickTarget(onSecondaryClick: { _ in onSecondaryAction() })
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
