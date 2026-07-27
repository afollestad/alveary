import AppKit
import SwiftData
import SwiftUI

enum SidebarThreadRowLayout {
    case project
    case topLevel
}

struct SidebarThreadRow: View {
    private static let statusIndicatorSize: CGFloat = 8
    static let cleanupButtonSize: CGFloat = 24
    private static let cleanupConfirmationWidth: CGFloat = 72
    private static let statusIndicatorSpacing: CGFloat = 8
    private static let provenanceIndicatorSize: CGFloat = 12
    private static let provenanceIndicatorSpacing: CGFloat = 6
    private static let worktreeIndicatorRotationDegrees: CGFloat = 90
    static let scheduledIndicatorAccessibilityLabel = "Scheduled task"
    static let cleanupWidthAnimationDuration = 0.18
    static let cleanupWidthAnimationNanoseconds: UInt64 = 180_000_000
    private static let cleanupHideAnimationDuration = 0.12
    private static let cleanupStatusTransitionDuration = 0.18
    static let cleanupConfirmationTimeoutNanoseconds: UInt64 = 500_000_000
    private static let cleanupDestructiveTint = Color(red: 0.74, green: 0.18, blue: 0.17)
    private static let cleanupDestructivePressedTint = Color(red: 0.54, green: 0.08, blue: 0.08)
    private static let trailingStatusCenterInset = SidebarProjectRow.horizontalPadding + statusIndicatorSize
    private static let cleanupButtonTrailingPadding = trailingStatusCenterInset - cleanupButtonSize / 2

    let thread: AgentThread
    let status: ThreadStatus
    let isSelected: Bool
    let layout: SidebarThreadRowLayout
    @Binding var editingThreadID: PersistentIdentifier?
    let cleanupAction: ThreadCleanupAction
    let cleanupDisabledReason: String?
    let suppressHoverAffordances: Bool
    let dragConfiguration: SidebarRowDragConfiguration?
    let onCommitRename: (String) -> Void
    let onConfirmCleanup: () -> Void

    @State var editText = ""
    @State private var initialEditText = ""
    @State var isHovering = false
    // The confirmation state machine lives in `SidebarView+ThreadRowCleanupConfirmation.swift`,
    // so everything it drives is internal rather than private.
    @State var isCleanupConfirmationArmed = false
    @State var isCleanupConfirmationChromeVisible = false
    @State var isCleanupControlCollapsing = false
    // Timeout collapse hides the affordance by shrinking to zero; hover collapse lands back on the icon.
    @State var isCleanupControlCollapsingToHidden = false
    @State var isHoveringCleanupButton = false
    @State var isCleanupButtonPressed = false
    @State var cleanupConfirmationDeadline: Date?
    @State var cleanupConfirmationRemainingNanoseconds: UInt64?
    @State var cleanupConfirmationResetTask: Task<Void, Never>?
    @State var cleanupWidthAnimationTask: Task<Void, Never>?
    @FocusState var isFieldFocused: Bool

    init(
        thread: AgentThread,
        status: ThreadStatus,
        isSelected: Bool,
        layout: SidebarThreadRowLayout = .project,
        editingThreadID: Binding<PersistentIdentifier?>,
        cleanupAction: ThreadCleanupAction = .archive,
        cleanupDisabledReason: String? = nil,
        suppressHoverAffordances: Bool = false,
        dragConfiguration: SidebarRowDragConfiguration? = nil,
        initialRowHover: Bool = false,
        initialCleanupButtonHover: Bool = false,
        initialCleanupConfirmationArmed: Bool = false,
        onCommitRename: @escaping (String) -> Void,
        onConfirmCleanup: @escaping () -> Void = {}
    ) {
        self.thread = thread
        self.status = status
        self.isSelected = isSelected
        self.layout = layout
        _editingThreadID = editingThreadID
        self.cleanupAction = cleanupAction
        self.cleanupDisabledReason = cleanupDisabledReason
        self.suppressHoverAffordances = suppressHoverAffordances
        self.dragConfiguration = dragConfiguration
        self.onCommitRename = onCommitRename
        self.onConfirmCleanup = onConfirmCleanup
        _isHovering = State(initialValue: initialRowHover)
        _isHoveringCleanupButton = State(initialValue: initialCleanupButtonHover)
        _isCleanupConfirmationArmed = State(initialValue: initialCleanupConfirmationArmed)
        _isCleanupConfirmationChromeVisible = State(initialValue: initialCleanupConfirmationArmed)
    }

    var isEditing: Bool { editingThreadID == thread.persistentModelID }

    var displayName: String { thread.displayName() }

    var body: some View {
        HStack(spacing: 0) {
            if layout == .project {
                Color.clear
                    .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)

                Color.clear
                    .frame(width: 10)
            }

            titleArea
                .sidebarDragSource(isEditing ? nil : dragConfiguration)

            trailingControls
        }
        .frame(height: SidebarRowMetrics.topLevelAndThreadContentHeight, alignment: .center)
        .padding(.trailing, trailingPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: Self.cleanupHideAnimationDuration)) {
                self.isHovering = isHovering
                if isHovering {
                    // Re-entering ends the collapse outright rather than waiting on
                    // `cleanupWidthAnimationTask`; `showsIcon` is gated on `isCleanupControlCollapsing`,
                    // so leaving it set would show an empty hover circle for up to 180ms. Either
                    // collapse variant can be in flight here (exit and re-enter within the window
                    // catches the land-on-icon one too), but both clear the `Confirm` chrome
                    // instantly at collapse start, so showing the icon is safe.
                    isCleanupControlCollapsing = false
                    isCleanupControlCollapsingToHidden = false
                } else {
                    isHoveringCleanupButton = false
                    if !isCleanupButtonPressed {
                        resumeCleanupConfirmation()
                    }
                }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                editText = displayName
                initialEditText = displayName
                isFieldFocused = true
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isEditing {
                commitRename()
            }
        }
        .accessibilityActions {
            // Gate the VoiceOver "Rename..." rotor action on `editingThreadID == nil`,
            // matching the context-menu button's gate (see `SidebarView.swift`). Without
            // this, VoiceOver users could bypass the guard and hit the SwiftUI unmount/
            // mount race that leaves the target row stuck in editing state without an
            // input field.
            if editingThreadID == nil, !suppressHoverAffordances {
                Button("Rename...") {
                    editingThreadID = thread.persistentModelID
                }
            }
        }
        .onDisappear {
            cleanupConfirmationResetTask?.cancel()
            cleanupWidthAnimationTask?.cancel()
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if status == .busy {
            StatusIndicatorSpinner(color: .secondary)
        } else {
            Circle()
                .fill(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .blue
        case .waitingForUser:
            return .blue
        case .unread:
            return .green
        case .error:
            return .red
        case .archived:
            return .secondary
        case .stopped:
            return .secondary
        }
    }

    private var trailingStatusOrCleanupControl: some View {
        ZStack(alignment: .trailing) {
            statusIndicator
                .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)
                .opacity(showsStatusIndicator ? 1 : 0)
                .scaleEffect(showsStatusIndicator ? 1 : 0.55)
                .animation(.easeInOut(duration: Self.cleanupStatusTransitionDuration), value: showsStatusIndicator)
                .frame(width: Self.cleanupButtonSize, height: Self.cleanupButtonSize, alignment: .center)

            if showsCleanupButton {
                cleanupButton
            }
        }
        .frame(width: trailingControlWidth, height: Self.cleanupButtonSize, alignment: .trailing)
        .clipped()
    }

    private var worktreeIndicator: some View {
        Image(systemName: "arrow.trianglehead.branch")
            .font(.system(size: Self.provenanceIndicatorSize, weight: .medium))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(Self.worktreeIndicatorRotationDegrees))
            .frame(width: Self.provenanceIndicatorSize, height: Self.provenanceIndicatorSize)
            .accessibilityHidden(true)
            .overlay {
                AppHoverTooltipAnchor(text: sidebarThreadWorktreeTooltipText(for: thread))
                    .frame(width: Self.provenanceIndicatorSize, height: Self.provenanceIndicatorSize)
            }
    }

    private var scheduledIndicator: some View {
        Image(systemName: "clock")
            .font(.system(size: Self.provenanceIndicatorSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Self.provenanceIndicatorSize, height: Self.provenanceIndicatorSize)
            .accessibilityLabel(Self.scheduledIndicatorAccessibilityLabel)
            .overlay {
                AppHoverTooltipAnchor(text: Self.scheduledIndicatorAccessibilityLabel)
                    .frame(width: Self.provenanceIndicatorSize, height: Self.provenanceIndicatorSize)
            }
    }

    private var trailingControls: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: trailingControlSpacing)

            if thread.scheduledTaskRun != nil {
                scheduledIndicator

                Color.clear
                    .frame(width: Self.provenanceIndicatorSpacing)
            }

            if thread.useWorktree {
                worktreeIndicator

                Color.clear
                    .frame(width: Self.provenanceIndicatorSpacing)
            }

            trailingStatusOrCleanupControl
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private var cleanupButton: some View {
        let visibility = sidebarThreadCleanupButtonVisibility(
            isConfirmationChromeVisible: isCleanupConfirmationChromeVisible,
            isCollapsing: isCleanupControlCollapsing
        )
        let showsConfirm = visibility.showsConfirm

        return cleanupButtonContent(showsConfirm: showsConfirm, showsIcon: visibility.showsIcon)
            .frame(width: cleanupControlWidth, height: Self.cleanupButtonSize, alignment: .trailing)
            .background(
                RoundedRectangle(cornerRadius: Self.cleanupButtonSize / 2, style: .continuous)
                    .fill(cleanupButtonBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cleanupButtonSize / 2, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.cleanupButtonSize / 2, style: .continuous))
            .gesture(cleanupPressGesture(width: cleanupControlWidth))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if cleanupDisabledReason == nil {
                    handleCleanupButtonClick()
                }
            }
            .allowsHitTesting(cleanupControlIsInteractive && cleanupDisabledReason == nil)
            .accessibilityLabel(showsConfirm ? "Confirm \(cleanupAction.label.lowercased()) thread" : "\(cleanupAction.label) thread")
            .accessibilityHidden(!cleanupControlIsInteractive)
            .accessibilityHint(cleanupDisabledReason ?? "")
            .disabled(cleanupDisabledReason != nil)
            .opacity(cleanupDisabledReason == nil ? 1 : 0.45)
            .help(cleanupDisabledReason == nil ? cleanupAction.label : "")
            .overlay {
                AppHoverTooltipAnchor(text: cleanupDisabledReason) { isHovering in
                    isHoveringCleanupButton = isHovering
                    if isHovering {
                        pauseCleanupConfirmation()
                    } else if !isCleanupButtonPressed {
                        resumeCleanupConfirmation()
                    }
                }
            }
            .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
            .animation(.easeOut(duration: 0.08), value: isCleanupButtonPressed)
    }

    private var showsCleanupButton: Bool {
        !suppressHoverAffordances && (isHovering || isCleanupConfirmationArmed || isCleanupControlCollapsing)
    }

    private var cleanupControlIsInteractive: Bool {
        !suppressHoverAffordances && (isHovering || isCleanupConfirmationArmed) && !isCleanupControlCollapsing
    }

    private var showsStatusIndicator: Bool {
        !showsCleanupButton || isCleanupControlCollapsingToHidden
    }

    private var cleanupControlWidth: CGFloat {
        if isCleanupControlCollapsingToHidden {
            return 0
        }
        return isCleanupConfirmationArmed ? Self.cleanupConfirmationWidth : Self.cleanupButtonSize
    }

    private var cleanupButtonBackgroundColor: Color {
        if isCleanupConfirmationChromeVisible {
            return isCleanupButtonPressed ? Self.cleanupDestructivePressedTint : Self.cleanupDestructiveTint
        }

        guard isHoveringCleanupButton || isCleanupButtonPressed else {
            return .clear
        }

        return Color.primary.opacity(isCleanupButtonPressed ? 0.24 : 0.12)
    }

    var iconForegroundColor: Color {
        .primary.opacity(isCleanupButtonPressed ? 0.95 : 0.82)
    }

    private var trailingControlWidth: CGFloat { max(Self.cleanupButtonSize, cleanupControlWidth) }

    private var trailingControlSpacing: CGFloat {
        Self.statusIndicatorSpacing
    }

    private var trailingPadding: CGFloat {
        Self.cleanupButtonTrailingPadding
    }

}

extension SidebarThreadRow {
    func commitRename() {
        if let committedName = sidebarThreadRenameCommitValue(
            initialValue: initialEditText,
            submittedValue: editText
        ) {
            onCommitRename(committedName)
        }
        editingThreadID = nil
    }

    func cancelRename() {
        editingThreadID = nil
    }
}
