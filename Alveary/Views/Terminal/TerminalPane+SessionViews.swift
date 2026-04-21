import SwiftUI

struct TerminalSessionChip: View {
    let session: TerminalSession
    let isSelected: Bool
    let action: () -> Void
    let onClose: () -> Void

    var body: some View {
        SelectableTabChip(
            displayName: session.chipLabel,
            statusColor: statusColor,
            isSelected: isSelected,
            selectAccessibilityLabel: accessibilityLabel,
            closeAccessibilityLabel: "Close \(plainChipLabel)",
            selectShortcut: nil,
            onSelect: action,
            onClose: onClose
        )
    }
}

private extension TerminalSessionChip {
    var statusColor: Color {
        switch session.status {
        case .running:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    var accessibilityLabel: String {
        "\(plainChipLabel), \(session.status.rawValue)"
    }

    var plainChipLabel: String {
        AppMarkdownInlineLabel.plainText(from: session.chipLabel)
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
            return .blue
        case .succeeded:
            return .green
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
