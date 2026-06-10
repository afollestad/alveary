import SwiftData
import SwiftUI

struct SidebarThreadRow: View {
    private static let statusIndicatorSize: CGFloat = 8
    private static let cleanupButtonSize: CGFloat = 24
    private static let cleanupConfirmationWidth: CGFloat = 72
    private static let statusIndicatorSpacing: CGFloat = 8
    private static let cleanupControlSpacing: CGFloat = 4
    private static let cleanupWidthAnimationDuration = 0.18
    private static let cleanupWidthAnimationNanoseconds: UInt64 = 180_000_000
    private static let cleanupHideAnimationDuration = 0.12
    private static let cleanupStatusTransitionDuration = 0.18
    private static let cleanupConfirmationTimeoutNanoseconds: UInt64 = 500_000_000
    private static let cleanupDestructiveTint = Color(red: 0.74, green: 0.18, blue: 0.17)
    private static let cleanupDestructivePressedTint = Color(red: 0.54, green: 0.08, blue: 0.08)
    private static let trailingStatusCenterInset = SidebarProjectRow.horizontalPadding + statusIndicatorSize
    private static let cleanupButtonTrailingPadding = trailingStatusCenterInset - cleanupButtonSize / 2
    private static let trailingStatusPadding = trailingStatusCenterInset - statusIndicatorSize / 2

    let thread: AgentThread
    let status: ThreadStatus
    let isSelected: Bool
    @Binding var editingThreadID: PersistentIdentifier?
    let cleanupAction: ThreadCleanupAction
    let onCommitRename: (String) -> Void
    let onConfirmCleanup: () -> Void

    @State private var editText = ""
    @State private var initialEditText = ""
    @State private var isHovering = false
    @State private var isCleanupConfirmationArmed = false
    @State private var isCleanupControlCollapsing = false
    // Timeout collapse hides the affordance by shrinking to zero; hover collapse lands back on the icon.
    @State private var isCleanupControlCollapsingToHidden = false
    @State private var isHoveringCleanupButton = false
    @State private var isCleanupButtonPressed = false
    @State private var cleanupConfirmationDeadline: Date?
    @State private var cleanupConfirmationRemainingNanoseconds: UInt64?
    @State private var cleanupConfirmationResetTask: Task<Void, Never>?
    @State private var cleanupWidthAnimationTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    init(
        thread: AgentThread,
        status: ThreadStatus,
        isSelected: Bool,
        editingThreadID: Binding<PersistentIdentifier?>,
        cleanupAction: ThreadCleanupAction = .archive,
        initialRowHover: Bool = false,
        initialCleanupConfirmationArmed: Bool = false,
        onCommitRename: @escaping (String) -> Void,
        onConfirmCleanup: @escaping () -> Void = {}
    ) {
        self.thread = thread
        self.status = status
        self.isSelected = isSelected
        _editingThreadID = editingThreadID
        self.cleanupAction = cleanupAction
        self.onCommitRename = onCommitRename
        self.onConfirmCleanup = onConfirmCleanup
        _isHovering = State(initialValue: initialRowHover)
        _isCleanupConfirmationArmed = State(initialValue: initialCleanupConfirmationArmed)
    }

    private var isEditing: Bool {
        editingThreadID == thread.persistentModelID
    }

    private var displayName: String {
        thread.displayName()
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)

            Color.clear
                .frame(width: 10)

            if isEditing {
                TextField("Thread name", text: $editText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AppMarkdownInlineLabel(text: displayName)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .layoutPriority(1)
            }

            Color.clear
                .frame(width: trailingControlSpacing)

            trailingStatusOrCleanupControl
        }
        .padding(.vertical, 6)
        .padding(.trailing, trailingPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if showsCleanupButton {
                cleanupButton
                    .padding(.trailing, Self.cleanupButtonTrailingPadding)
            }
        }
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: Self.cleanupHideAnimationDuration)) {
                self.isHovering = isHovering
                if isHovering {
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
            if editingThreadID == nil {
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
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.5)
                .tint(.blue)
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
        statusIndicator
            .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)
            .opacity(showsStatusIndicator ? 1 : 0)
            .scaleEffect(showsStatusIndicator ? 1 : 0.55)
            .animation(.easeInOut(duration: Self.cleanupStatusTransitionDuration), value: showsStatusIndicator)
            .frame(width: trailingControlWidth, height: Self.cleanupButtonSize, alignment: .trailing)
    }

    private var cleanupButton: some View {
        let showsConfirm = showsCleanupConfirmation

        return cleanupButtonContent(showsConfirm: showsConfirm)
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
                handleCleanupButtonClick()
            }
            .allowsHitTesting(cleanupControlIsInteractive)
            .onHover { isHovering in
                isHoveringCleanupButton = isHovering

                if isHovering {
                    pauseCleanupConfirmation()
                } else if !isCleanupButtonPressed {
                    resumeCleanupConfirmation()
                }
            }
            .accessibilityLabel(showsConfirm ? "Confirm \(cleanupAction.label.lowercased()) thread" : "\(cleanupAction.label) thread")
            .accessibilityHidden(!cleanupControlIsInteractive)
            .help(cleanupAction.label)
            .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
            .animation(.easeOut(duration: 0.08), value: isCleanupButtonPressed)
            .animation(.easeInOut(duration: Self.cleanupWidthAnimationDuration), value: isCleanupConfirmationArmed)
            .frame(width: Self.cleanupConfirmationWidth, height: Self.cleanupButtonSize, alignment: .trailing)
    }

    private func cleanupButtonContent(showsConfirm: Bool) -> some View {
        ZStack(alignment: .trailing) {
            Text("Confirm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showsConfirm ? 1 : 0)

            Image(systemName: cleanupAction.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconForegroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showsConfirm ? 0 : 1)
        }
    }

    private var showsCleanupButton: Bool {
        isHovering || isCleanupConfirmationArmed || isCleanupControlCollapsing
    }

    private var cleanupControlIsInteractive: Bool {
        (isHovering || isCleanupConfirmationArmed) && !isCleanupControlCollapsing
    }

    private var showsStatusIndicator: Bool {
        !showsCleanupButton || isCleanupControlCollapsingToHidden
    }

    private var showsCleanupConfirmation: Bool {
        isCleanupConfirmationArmed || isCleanupControlCollapsing
    }

    private var cleanupControlWidth: CGFloat {
        if isCleanupControlCollapsingToHidden {
            return 0
        }
        return isCleanupConfirmationArmed ? Self.cleanupConfirmationWidth : Self.cleanupButtonSize
    }

    private var cleanupButtonBackgroundColor: Color {
        if showsCleanupConfirmation {
            return isCleanupButtonPressed ? Self.cleanupDestructivePressedTint : Self.cleanupDestructiveTint
        }

        return Color.primary.opacity(isCleanupButtonPressed ? 0.24 : 0.12)
    }

    private var iconForegroundColor: Color {
        .primary.opacity(isCleanupButtonPressed ? 0.95 : 0.82)
    }

    private var trailingControlWidth: CGFloat {
        guard showsCleanupButton else {
            return Self.statusIndicatorSize
        }
        return max(Self.statusIndicatorSize, cleanupControlWidth)
    }

    private var trailingControlSpacing: CGFloat {
        showsCleanupButton && !isCleanupControlCollapsingToHidden ? Self.cleanupControlSpacing : Self.statusIndicatorSpacing
    }

    private var trailingPadding: CGFloat {
        showsCleanupButton && !isCleanupControlCollapsingToHidden ? Self.cleanupButtonTrailingPadding : Self.trailingStatusPadding
    }

    private func cleanupPressGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isCleanupButtonPressed else {
                    return
                }

                setCleanupButtonPressed(true)
                pauseCleanupConfirmation()
            }
            .onEnded { value in
                let wasArmed = isCleanupConfirmationArmed
                setCleanupButtonPressed(false)

                if cleanupButtonContains(value.location, width: width) {
                    handleCleanupButtonClick()
                } else if wasArmed && !isHoveringCleanupButton {
                    resumeCleanupConfirmation()
                }
            }
    }

    private func cleanupButtonContains(_ location: CGPoint, width: CGFloat) -> Bool {
        location.x >= 0
            && location.x <= width
            && location.y >= 0
            && location.y <= Self.cleanupButtonSize
    }

    private func setCleanupButtonPressed(_ pressed: Bool) {
        withAnimation(.easeOut(duration: 0.08)) {
            isCleanupButtonPressed = pressed
        }
    }

    private func handleCleanupButtonClick() {
        if isCleanupConfirmationArmed {
            clearCleanupConfirmation()
            onConfirmCleanup()
        } else {
            armCleanupConfirmation()
        }
    }

    private func armCleanupConfirmation() {
        cleanupConfirmationResetTask?.cancel()
        cleanupConfirmationRemainingNanoseconds = nil
        cleanupWidthAnimationTask?.cancel()
        isCleanupControlCollapsing = false
        isCleanupControlCollapsingToHidden = false

        withAnimation(.easeInOut(duration: Self.cleanupWidthAnimationDuration)) {
            isCleanupConfirmationArmed = true
        }
        scheduleCleanupConfirmationTimeout(nanoseconds: Self.cleanupConfirmationTimeoutNanoseconds)
        if isHoveringCleanupButton {
            pauseCleanupConfirmation()
        }
    }

    private func scheduleCleanupConfirmationTimeout(nanoseconds: UInt64) {
        cleanupConfirmationDeadline = Date().addingTimeInterval(Double(nanoseconds) / 1_000_000_000)

        cleanupConfirmationResetTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                clearCleanupConfirmation()
            }
        }
    }

    private func pauseCleanupConfirmation() {
        guard isCleanupConfirmationArmed,
              cleanupConfirmationResetTask != nil,
              cleanupConfirmationRemainingNanoseconds == nil else {
            return
        }

        cleanupConfirmationResetTask?.cancel()
        cleanupConfirmationResetTask = nil
        let remainingSeconds = max(cleanupConfirmationDeadline?.timeIntervalSinceNow ?? 0, 0)
        cleanupConfirmationDeadline = nil
        cleanupConfirmationRemainingNanoseconds = UInt64(remainingSeconds * 1_000_000_000)
    }

    private func resumeCleanupConfirmation() {
        guard isCleanupConfirmationArmed,
              let remainingNanoseconds = cleanupConfirmationRemainingNanoseconds else {
            return
        }

        cleanupConfirmationRemainingNanoseconds = nil
        scheduleCleanupConfirmationTimeout(nanoseconds: remainingNanoseconds)
    }

    private func clearCleanupConfirmation() {
        cleanupConfirmationResetTask?.cancel()
        cleanupConfirmationResetTask = nil
        cleanupWidthAnimationTask?.cancel()
        cleanupConfirmationDeadline = nil
        cleanupConfirmationRemainingNanoseconds = nil

        guard isCleanupConfirmationArmed else {
            return
        }

        let shouldHideAfterCollapse = !isHovering

        withAnimation(.easeInOut(duration: Self.cleanupWidthAnimationDuration)) {
            isCleanupControlCollapsing = true
            isCleanupControlCollapsingToHidden = shouldHideAfterCollapse
            isCleanupConfirmationArmed = false
        }

        cleanupWidthAnimationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.cleanupWidthAnimationNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            isCleanupControlCollapsing = false
            isCleanupControlCollapsingToHidden = false
        }
    }

    private func commitRename() {
        if let committedName = sidebarThreadRenameCommitValue(
            initialValue: initialEditText,
            submittedValue: editText
        ) {
            onCommitRename(committedName)
        }
        editingThreadID = nil
    }

    private func cancelRename() {
        editingThreadID = nil
    }
}

/// Returns the trimmed name to commit, or `nil` when the submission is empty or unchanged from
/// the name shown when editing began. Skipping unchanged submissions matters because committing
/// sets `hasCustomName`, which would pin an auto-generated title (see `renameThread`).
func sidebarThreadRenameCommitValue(initialValue: String, submittedValue: String) -> String? {
    let trimmedInitial = initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSubmitted = submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSubmitted.isEmpty, trimmedSubmitted != trimmedInitial else {
        return nil
    }
    return trimmedSubmitted
}
