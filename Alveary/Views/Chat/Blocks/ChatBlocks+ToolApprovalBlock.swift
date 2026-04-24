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

    private var isBatch: Bool {
        approvals.count > 1
    }

    private var title: String {
        isBatch ? "Approve tool uses?" : approval.approvalPromptCopy.title
    }

    private var displayName: String {
        guard isBatch else {
            return approval.displayName
        }

        let names = Set(approvals.map(\.displayName))
        guard names.count == 1,
              let name = names.first else {
            return "\(approvals.count) tool uses"
        }

        switch name {
        case "Bash command":
            return "\(approvals.count) Bash commands"
        default:
            return "\(approvals.count) tool uses"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    if approval.approvalPromptCopy.showsDisplayName {
                        Text(displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(approvals) { approval in
                            Text(approval.conciseSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            actionLayout
                .controlSize(.small)
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

    @ViewBuilder
    private var actionLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                actionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isDenied {
            denyButton(title: approval.approvalPromptCopy.deniedTitle)
        } else if isSuperseded {
            supersededButton
        } else if isOneShotApproved {
            approveButton(title: approval.approvalPromptCopy.approvedTitle)
        } else if let resolvedSessionTitle {
            sessionApprovalButton(title: resolvedSessionTitle, isResolved: true)
        } else {
            pendingApproveButton
            denyButton(title: approval.approvalPromptCopy.denyTitle)
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
    private var pendingApproveButton: some View {
        if sessionApprovalScopes.isEmpty {
            approveButton(title: approval.approvalPromptCopy.approveTitle)
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
        }
    }

    @ViewBuilder
    private func sessionApprovalButton(title: String, isResolved: Bool) -> some View {
        Button {
            if let scope = sessionApprovalScopes.first {
                onApproveForSession(scope)
            }
        } label: {
            actionLabel(title: title, systemImage: "clock.badge.checkmark")
        }
        .secondaryActionButtonStyle()
        .disabled(isResolved || actionsAreDisabled || sessionApprovalScopes.isEmpty)
    }

    private func approveButton(title: String) -> some View {
        Button {
            onApprove()
        } label: {
            actionLabel(title: title, systemImage: "checkmark")
        }
        .primaryActionButtonStyle()
        .disabled(actionsAreDisabled)
    }

    private func denyButton(title: String) -> some View {
        Button {
            onDeny()
        } label: {
            actionLabel(title: title, systemImage: "xmark")
        }
        .secondaryActionButtonStyle()
        .disabled(actionsAreDisabled)
    }

    private var supersededButton: some View {
        Button(action: {}, label: {
            actionLabel(title: "Superseded", systemImage: "arrow.trianglehead.clockwise")
        })
        .secondaryActionButtonStyle()
        .disabled(true)
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
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
