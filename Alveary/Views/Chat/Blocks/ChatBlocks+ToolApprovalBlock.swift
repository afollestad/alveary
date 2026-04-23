import SwiftUI

struct ToolApprovalBlock: View {
    let approval: ToolApprovalRequest
    let status: ToolApprovalStatus?
    let onApprove: () -> Void
    let onDeny: () -> Void

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    private var actionsAreDisabled: Bool {
        status != .pending
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

            HStack(spacing: 8) {
                if !isDenied {
                    Button {
                        onApprove()
                    } label: {
                        actionLabel(title: approveTitle, systemImage: approveIcon)
                    }
                    .primaryActionButtonStyle()
                    .disabled(actionsAreDisabled)
                }

                if !isApproved {
                    Button {
                        onDeny()
                    } label: {
                        actionLabel(title: denyTitle, systemImage: denyIcon)
                    }
                    .secondaryActionButtonStyle()
                    .disabled(actionsAreDisabled)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, chatBlockPadding)
        .padding(.vertical, chatVerticalPadding)
        .bubbleBackground(maxWidth: bubbleMaxWidth)
    }

    private var approveTitle: String {
        isApproved ? "Approved" : "Approve"
    }

    private var denyTitle: String {
        isDenied ? "Denied" : "Deny"
    }

    private var approveIcon: String {
        "checkmark"
    }

    private var denyIcon: String {
        "xmark"
    }

    private var isApproved: Bool {
        status == .approving || status == .approved
    }

    private var isDenied: Bool {
        status == .denying || status == .denied
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }
}
