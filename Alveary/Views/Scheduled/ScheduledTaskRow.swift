import SwiftUI

struct ScheduledTaskRow: View {
    let task: ScheduledTaskRowPresentation
    let providerName: String
    let isRunNowPending: Bool
    let onEdit: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onRunNow: () -> Void
    let onDelete: () -> Void
    let editFocus: FocusState<String?>.Binding
    let editFocusID: String

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)

                ScheduledTaskStateBadge(state: task.state)

                Spacer(minLength: 8)

                Text(providerName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(task.prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                ScheduledTaskMetadataLabel(
                    systemImage: "repeat",
                    text: ScheduledTaskPresentationFormatting.recurrenceSummary(
                        task.recurrence,
                        timeZoneIdentifier: task.timeZoneIdentifier,
                        locale: locale
                    )
                )
                ScheduledTaskMetadataLabel(systemImage: "folder", text: task.workspaceSummary)

                if let nextOccurrenceAt = task.nextOccurrenceAt {
                    ScheduledTaskMetadataLabel(
                        systemImage: "clock",
                        text: "Next: " + ScheduledTaskPresentationFormatting.dateTime(
                            nextOccurrenceAt,
                            timeZoneIdentifier: task.timeZoneIdentifier,
                            locale: locale
                        )
                    )
                }
            }

            if let blockedReason = task.blockedReason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(blockedReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Paused reason: \(blockedReason)")
            }

            ScheduledTaskRowActions(
                task: task,
                isRunNowPending: isRunNowPending,
                onEdit: onEdit,
                onPause: onPause,
                onResume: onResume,
                onRunNow: onRunNow,
                onDelete: onDelete,
                editFocus: editFocus,
                editFocusID: editFocusID
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
    }
}

private struct ScheduledTaskMetadataLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScheduledTaskStateBadge: View {
    let state: ScheduledTaskState

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
            .accessibilityLabel("State: \(label)")
    }

    private var label: String {
        switch state {
        case .active:
            "Active"
        case .paused:
            "Paused"
        case .completed:
            "Completed"
        }
    }

    private var color: Color {
        switch state {
        case .active:
            .green
        case .paused:
            .orange
        case .completed:
            .secondary
        }
    }
}

private struct ScheduledTaskRowActions: View {
    let task: ScheduledTaskRowPresentation
    let isRunNowPending: Bool
    let onEdit: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onRunNow: () -> Void
    let onDelete: () -> Void
    let editFocus: FocusState<String?>.Binding
    let editFocusID: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actions
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    runNowButton
                    editButton
                }
                HStack(spacing: 10) {
                    stateButton
                    deleteButton
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        runNowButton
        editButton
        Spacer()
        stateButton
        deleteButton
    }

    private var runNowButton: some View {
        Button(action: onRunNow) {
            HStack(spacing: 6) {
                if isRunNowPending {
                    ProgressView()
                        .controlSize(.small)
                    Text("Starting")
                } else {
                    Image(systemName: "play.fill")
                    Text("Run now")
                }
            }
        }
        .secondaryActionButtonStyle()
        .disabled(!task.canRunNow || isRunNowPending)
        .help(task.hasActiveRun ? "Run now is unavailable while this task is running or waiting." : "Run this task now")
    }

    private var editButton: some View {
        Button("Edit", action: onEdit)
            .secondaryActionButtonStyle()
            .focused(editFocus, equals: editFocusID)
    }

    @ViewBuilder private var stateButton: some View {
        if task.canPause {
            Button("Pause", action: onPause)
                .secondaryActionButtonStyle()
        } else if task.canResume {
            Button("Resume", action: onResume)
                .secondaryActionButtonStyle()
        }
    }

    private var deleteButton: some View {
        Button("Delete", role: .destructive, action: onDelete)
            .destructiveActionButtonStyle()
    }
}
