import SwiftUI

struct TerminalSessionChip: View {
    let session: TerminalSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(session.title)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
        "\(session.title), \(session.status.rawValue)"
    }
}

struct TerminalSessionMenuRow: View {
    let session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)

            if let detail = session.threadName ?? session.projectName ?? session.currentDirectory {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TerminalSessionMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
