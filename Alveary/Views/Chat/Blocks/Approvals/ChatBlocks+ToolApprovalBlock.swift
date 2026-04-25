import SwiftUI

struct ToolApprovalBlock: View {
    let approval: ToolApprovalRequest
    let approvals: [ToolApprovalRequest]
    let status: ToolApprovalStatus?
    let isBlocked: Bool
    let onApprove: () -> Void
    let onApproveForSession: (ToolApprovalSessionScope) -> Void
    let loadApprovalSelection: () async -> ToolApprovalSelection?
    let onSelectApprovalSelection: (ToolApprovalSelection) -> Void
    let onDeny: () -> Void

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth
    @State private var selectedApprovalSelection: ToolApprovalSelection
    @State private var selectionGeneration = 0
    @Namespace private var actionButtonNamespace

    init(
        approval: ToolApprovalRequest,
        approvals: [ToolApprovalRequest]? = nil,
        status: ToolApprovalStatus?,
        isBlocked: Bool = false,
        onApprove: @escaping () -> Void,
        onApproveForSession: @escaping (ToolApprovalSessionScope) -> Void,
        onDeny: @escaping () -> Void,
        loadApprovalSelection: @escaping () async -> ToolApprovalSelection? = { nil },
        onSelectApprovalSelection: @escaping (ToolApprovalSelection) -> Void = { _ in }
    ) {
        self.approval = approval
        self.approvals = approvals ?? [approval]
        self.status = status
        self.isBlocked = isBlocked
        self.onApprove = onApprove
        self.onApproveForSession = onApproveForSession
        self.loadApprovalSelection = loadApprovalSelection
        self.onSelectApprovalSelection = onSelectApprovalSelection
        self.onDeny = onDeny
        _selectedApprovalSelection = State(initialValue: .once)
    }

    private var actionsAreDisabled: Bool {
        status != .pending || isBlocked
    }

    private var sessionApprovalScopes: [ToolApprovalSessionScope] {
        let allApprovalScopes = approvals.map { Set($0.supportedSessionApprovalScopes) }
        guard !allApprovalScopes.isEmpty else {
            return approval.supportedSessionApprovalScopes
        }
        return approval.supportedSessionApprovalScopes.filter { scope in
            allApprovalScopes.allSatisfy { $0.contains(scope) }
        }
    }

    private var title: String {
        ToolApprovalRequest.approvalPromptTitle(for: approvals)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TranscriptStaticHeaderRow(title: title, systemImage: "lock.fill", bottomPadding: 0, fillsWidth: false)

            approvalSummary
                .padding(.top, toolApprovalActionsTopSpacing)
                .padding(.leading, transcriptToolDetailLeadingInset)

            actionLayout
                .controlSize(.small)
                .padding(.top, toolApprovalActionsTopSpacing)
                .padding(.leading, transcriptToolDetailLeadingInset)
        }
        .padding(.horizontal, chatBlockPadding)
        .padding(.vertical, chatVerticalPadding)
        .bubbleBackground(maxWidth: bubbleMaxWidth)
        .onChange(of: approvalSelectionIdentityID) { _, _ in
            resetSelection()
        }
        .task(id: approvalSelectionLoadID) {
            await loadPersistedSelection()
        }
    }

    private var approvalSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(approvals) { approval in
                ApprovalSummaryLine(approval: approval)
            }
        }
        .font(.system(size: transcriptToolApprovalBodyFontSize))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var actionLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                // `ViewThatFits` keeps fallback candidates alive for layout; only
                // the primary row can own matched-geometry endpoints.
                actionButtons(enableMatchedGeometry: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                actionButtons(enableMatchedGeometry: false)
            }
        }
        .animation(toolExpansionAnimation, value: actionAnimationID)
    }

    @ViewBuilder
    private func actionButtons(enableMatchedGeometry: Bool) -> some View {
        if isDenied {
            denyButton(title: approval.approvalPromptCopy.deniedTitle, enableMatchedGeometry: enableMatchedGeometry)
            hiddenPendingApproveButton
        } else if isSuperseded {
            supersededButton()
            hiddenPendingApproveButton
        } else if isOneShotApproved {
            approveButton(title: approval.approvalPromptCopy.approvedTitle, enableMatchedGeometry: enableMatchedGeometry)
            hiddenPendingDenyButton
        } else if let resolvedSessionTitle {
            sessionApprovalButton(title: resolvedSessionTitle, isResolved: true, enableMatchedGeometry: enableMatchedGeometry)
            hiddenPendingDenyButton
        } else {
            pendingApproveButton(enableMatchedGeometry: enableMatchedGeometry)
            denyButton(title: approval.approvalPromptCopy.denyTitle, enableMatchedGeometry: enableMatchedGeometry)
        }
    }

    private var normalizedSelectedApprovalSelection: ToolApprovalSelection {
        selectedApprovalSelection.normalized(for: sessionApprovalScopes)
    }

    private var pendingApprovalTitle: String {
        pendingApprovalMenuTitle(for: normalizedSelectedApprovalSelection)
    }

    private func pendingSessionApprovalTitle(for scope: ToolApprovalSessionScope) -> String {
        if sessionApprovalScopes.count == 1 {
            return "Approve for session"
        }
        return scope.pendingTitle
    }

    private var pendingApprovalMenuModes: [ToolApprovalSelection] {
        [.once] + sessionApprovalScopes.map(ToolApprovalSelection.init(sessionScope:))
    }

    private var approvalSelectionIdentityID: String {
        approval.sessionId + "\u{0}" + approval.toolUseId
    }

    private var approvalSelectionLoadID: String {
        approvalSelectionIdentityID + "\u{0}" + (status?.rawValue ?? "none")
    }

    private var actionAnimationID: String {
        status?.rawValue ?? "pending"
    }

    private var shouldLoadApprovalSelection: Bool {
        !sessionApprovalScopes.isEmpty && status == .pending
    }

    private var resolvedSessionTitle: String? {
        guard let status else {
            return nil
        }

        switch status {
        case .approvingForSessionExact, .approvedForSessionExact:
            return sessionApprovalScopes.count == 1 ? "Approved for session" : ToolApprovalSessionScope.exact.resolvedTitle
        case .approvingForSessionGroup, .approvedForSessionGroup:
            return ToolApprovalSessionScope.group.resolvedTitle
        default:
            return nil
        }
    }

    private var isOneShotApproved: Bool {
        status == .approving || status == .approved
    }

    private var isDenied: Bool {
        status == .denying || status == .denied
    }

    private var isSuperseded: Bool {
        status == .superseded
    }

    @ViewBuilder
    private func pendingApproveButton(isLayoutPlaceholder: Bool = false, enableMatchedGeometry: Bool = false) -> some View {
        if sessionApprovalScopes.isEmpty {
            approveButton(
                title: approval.approvalPromptCopy.approveTitle,
                isLayoutPlaceholder: isLayoutPlaceholder,
                enableMatchedGeometry: enableMatchedGeometry
            )
        } else {
            SplitActionButton(
                title: pendingApprovalTitle,
                systemImage: "checkmark",
                selectedOption: normalizedSelectedApprovalSelection,
                options: pendingApprovalMenuModes,
                optionTitle: pendingApprovalMenuTitle(for:),
                action: submitPendingApproval,
                selectOption: { selection in
                    selectApprovalSelection(selection)
                }
            )
            .disabled(actionsAreDisabled)
            .toolApprovalMatchedAction(
                actionMatchID(
                    ToolApprovalMatchedActionID.approve,
                    isLayoutPlaceholder: isLayoutPlaceholder,
                    enableMatchedGeometry: enableMatchedGeometry
                ),
                in: actionButtonNamespace
            )
        }
    }

    private var hiddenPendingApproveButton: some View {
        // Invisible placeholders preserve the pending prompt width after one
        // action resolves without introducing extra matched-geometry targets.
        pendingApproveButton(isLayoutPlaceholder: true)
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var hiddenPendingDenyButton: some View {
        denyButton(title: approval.approvalPromptCopy.denyTitle, isLayoutPlaceholder: true)
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sessionApprovalButton(title: String, isResolved: Bool, enableMatchedGeometry: Bool) -> some View {
        Button {
            if let scope = sessionApprovalScopes.first {
                onApproveForSession(scope)
            }
        } label: {
            actionLabel(title: title, systemImage: "clock.badge.checkmark")
        }
        .secondaryActionButtonStyle()
        .disabled(isResolved || actionsAreDisabled || sessionApprovalScopes.isEmpty)
        .toolApprovalMatchedAction(
            actionMatchID(
                ToolApprovalMatchedActionID.approve,
                isLayoutPlaceholder: false,
                enableMatchedGeometry: enableMatchedGeometry
            ),
            in: actionButtonNamespace
        )
    }

    private func approveButton(
        title: String,
        isLayoutPlaceholder: Bool = false,
        enableMatchedGeometry: Bool = false
    ) -> some View {
        Button {
            onApprove()
        } label: {
            actionLabel(title: title, systemImage: "checkmark")
        }
        .primaryActionButtonStyle()
        .disabled(actionsAreDisabled)
        .toolApprovalMatchedAction(
            actionMatchID(
                ToolApprovalMatchedActionID.approve,
                isLayoutPlaceholder: isLayoutPlaceholder,
                enableMatchedGeometry: enableMatchedGeometry
            ),
            in: actionButtonNamespace
        )
    }

    private func denyButton(
        title: String,
        isLayoutPlaceholder: Bool = false,
        enableMatchedGeometry: Bool = false
    ) -> some View {
        Button {
            onDeny()
        } label: {
            actionLabel(title: title, systemImage: "xmark")
        }
        .secondaryActionButtonStyle()
        .disabled(actionsAreDisabled)
        .toolApprovalMatchedAction(
            actionMatchID(
                ToolApprovalMatchedActionID.deny,
                isLayoutPlaceholder: isLayoutPlaceholder,
                enableMatchedGeometry: enableMatchedGeometry
            ),
            in: actionButtonNamespace
        )
    }

    private func supersededButton() -> some View {
        Button(action: {}, label: {
            actionLabel(title: "Superseded", systemImage: "arrow.trianglehead.clockwise")
        })
        .secondaryActionButtonStyle()
        .disabled(true)
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private func actionMatchID(_ id: String, isLayoutPlaceholder: Bool, enableMatchedGeometry: Bool) -> String? {
        if isLayoutPlaceholder || !enableMatchedGeometry {
            return nil
        }
        return id
    }

    private func pendingApprovalMenuTitle(for selection: ToolApprovalSelection) -> String {
        switch selection {
        case .once:
            return "Approve once"
        case .sessionExact, .sessionGroup:
            guard let scope = selection.sessionScope else {
                return "Approve for session"
            }
            return pendingSessionApprovalTitle(for: scope)
        }
    }

    private func submitPendingApproval() {
        guard let scope = normalizedSelectedApprovalSelection.sessionScope else {
            onApprove()
            return
        }
        onApproveForSession(scope)
    }

    private func selectApprovalSelection(_ selection: ToolApprovalSelection) {
        let normalizedSelection = selection.normalized(for: sessionApprovalScopes)
        selectionGeneration += 1
        selectedApprovalSelection = normalizedSelection
        onSelectApprovalSelection(normalizedSelection)
    }

    private func resetSelection() {
        selectionGeneration += 1
        selectedApprovalSelection = .once
    }

    private func loadPersistedSelection() async {
        guard shouldLoadApprovalSelection else {
            return
        }

        let generation = selectionGeneration
        let selection = await loadApprovalSelection()
        guard generation == selectionGeneration else {
            return
        }

        selectedApprovalSelection = (selection ?? .once).normalized(for: sessionApprovalScopes)
    }
}

private struct ApprovalSummaryLine: View {
    let approval: ToolApprovalRequest

    var body: some View {
        if approval.toolName == "Bash" {
            commandChip
        } else {
            Text(approval.conciseSummary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var commandChip: some View {
        Text(approval.conciseSummary)
            .font(.system(size: transcriptToolApprovalBodyFontSize, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, approvalCommandChipHPadding)
            .padding(.vertical, approvalCommandChipVPadding)
            .background(
                RoundedRectangle(cornerRadius: approvalCommandChipCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
            )
    }
}

private enum ToolApprovalMatchedActionID {
    static let approve = "approve"
    static let deny = "deny"
}

private extension View {
    @ViewBuilder
    func toolApprovalMatchedAction(_ id: String?, in namespace: Namespace.ID) -> some View {
        if let id {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
