import SwiftUI

struct TerminalSessionChip: View {
    let session: TerminalSession
    let isSelected: Bool
    let action: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(session.chipLabel)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(session.chipLabel)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? AppSelectionStyle.rowFill : Color.secondary.opacity(0.08))
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private extension TerminalSessionChip {
    var statusColor: Color {
        switch session.status {
        case .running:
            return .green
        case .succeeded:
            return .blue
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    var accessibilityLabel: String {
        "\(session.chipLabel), \(session.status.rawValue)"
    }
}

struct TerminalSessionMenuRow: View {
    let session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.chipLabel)

            if let detail = session.projectName ?? session.currentDirectory {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TerminalSessionContextRow: View {
    let projectName: String?
    let currentDirectory: String?

    var body: some View {
        HStack(spacing: 8) {
            if let projectName = normalizedProjectName {
                Text(projectName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if normalizedProjectName != nil, normalizedDirectory != nil {
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 3, height: 3)
            }

            if let currentDirectory = normalizedDirectory {
                Text(currentDirectory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
        }
    }
}

private extension TerminalSessionContextRow {
    var normalizedProjectName: String? {
        normalized(projectName)
    }

    var normalizedDirectory: String? {
        normalized(currentDirectory)
    }

    func normalized(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }
}

struct TerminalSessionStatusBadge: View {
    let status: TerminalSession.Status

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
    }
}

private extension TerminalSessionStatusBadge {
    var label: String {
        switch status {
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var foregroundColor: Color {
        switch status {
        case .running:
            return .green
        case .succeeded:
            return .blue
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }
}
