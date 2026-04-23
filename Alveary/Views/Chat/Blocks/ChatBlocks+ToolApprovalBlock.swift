import SwiftUI

struct ToolApprovalBlock: View {
    let approval: ToolApprovalRequest
    let status: ToolApprovalStatus?
    let onApprove: () -> Void
    let onApproveForSession: (ToolApprovalSessionScope) -> Void
    let onDeny: () -> Void

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth
    @State private var selectedSessionScope: ToolApprovalSessionScope

    init(
        approval: ToolApprovalRequest,
        status: ToolApprovalStatus?,
        onApprove: @escaping () -> Void,
        onApproveForSession: @escaping (ToolApprovalSessionScope) -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.approval = approval
        self.status = status
        self.onApprove = onApprove
        self.onApproveForSession = onApproveForSession
        self.onDeny = onDeny
        _selectedSessionScope = State(initialValue: approval.supportedSessionApprovalScopes.first ?? .exact)
    }

    private var actionsAreDisabled: Bool {
        status != .pending
    }

    private var sessionApprovalScopes: [ToolApprovalSessionScope] {
        approval.supportedSessionApprovalScopes
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
                    Text("Approve tool use?")
                        .font(.subheadline.weight(.semibold))

                    Text(approval.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(approval.conciseSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            actionLayout
                .controlSize(.small)
        }
        .padding(.horizontal, chatBlockPadding)
        .padding(.vertical, chatVerticalPadding)
        .bubbleBackground(maxWidth: bubbleMaxWidth)
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
            denyButton(title: "Denied")
        } else if isSuperseded {
            supersededButton
        } else if isOneShotApproved {
            approveButton(title: "Approved")
        } else if let resolvedSessionTitle {
            sessionApprovalButton(title: resolvedSessionTitle, isResolved: true)
        } else {
            approveButton(title: "Approve")

            if !sessionApprovalScopes.isEmpty {
                sessionApprovalButton(title: pendingSessionApprovalTitle, isResolved: false)
            }

            denyButton(title: "Deny")
        }
    }

    private var pendingSessionApprovalTitle: String {
        if sessionApprovalScopes.count == 1 {
            return "Approve for session"
        }
        return selectedSessionScope.pendingTitle
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
    private func sessionApprovalButton(title: String, isResolved: Bool) -> some View {
        if sessionApprovalScopes.count > 1 && !isResolved {
            ToolApprovalSessionSplitButton(
                title: title,
                selectedScope: selectedSessionScope,
                availableScopes: sessionApprovalScopes,
                action: {
                    onApproveForSession(selectedSessionScope)
                },
                selectScope: { scope in
                    selectedSessionScope = scope
                }
            )
            .disabled(actionsAreDisabled)
        } else {
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
}

private struct ToolApprovalSessionSplitButton: View {
    let title: String
    let selectedScope: ToolApprovalSessionScope
    let availableScopes: [ToolApprovalSessionScope]
    let action: () -> Void
    let selectScope: (ToolApprovalSessionScope) -> Void

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Label(title, systemImage: "clock.badge.checkmark")
                    .lineLimit(1)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: controlHeight)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(isEnabled ? 0.12 : 0.06))
                .frame(width: 1)
                .padding(.vertical, 4)

            Menu {
                ForEach(availableScopes, id: \.self) { scope in
                    Button {
                        selectScope(scope)
                    } label: {
                        if scope == selectedScope {
                            Label(scope.pendingTitle, systemImage: "checkmark")
                        } else {
                            Text(scope.pendingTitle)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .frame(width: menuWidth, height: controlHeight)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary.opacity(isEnabled ? 1 : 0.78))
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var backgroundColor: Color {
        isEnabled ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05)
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 10
        case .regular:
            return 12
        case .large:
            return 14
        case .extraLarge:
            return 16
        @unknown default:
            return 12
        }
    }

    private var controlHeight: CGFloat {
        switch controlSize {
        case .mini:
            return 22
        case .small:
            return 24
        case .regular:
            return 30
        case .large:
            return 34
        case .extraLarge:
            return 38
        @unknown default:
            return 30
        }
    }

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 9
        case .regular:
            return 10
        case .large:
            return 12
        case .extraLarge:
            return 14
        @unknown default:
            return 10
        }
    }

    private var menuWidth: CGFloat {
        switch controlSize {
        case .mini:
            return 22
        case .small:
            return 24
        case .regular:
            return 28
        case .large:
            return 30
        case .extraLarge:
            return 34
        @unknown default:
            return 28
        }
    }
}
