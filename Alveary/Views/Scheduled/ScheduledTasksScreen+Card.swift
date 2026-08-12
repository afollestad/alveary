import SwiftUI

struct ScheduledTaskCard: View, Equatable {
    let task: ScheduledTaskRowPresentation
    let providerName: String
    let isRunNowPending: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onRunNow: () -> Void
    let onDelete: () -> Void
    let cardFocus: FocusState<String?>.Binding
    let cardFocusID: String

    @Environment(\.locale) private var locale

    /// The five actions and the focus binding are excluded: each action closes over the
    /// `task` compared here plus the screen's view-model reference or its `@State`
    /// confirmation box, and the binding reads the screen's `@FocusState` storage — none
    /// of which a captured copy can serve staler than a fresh one. `isSelected` is compared
    /// because it drives the card's fill. `locale` is an `@Environment` read, so it
    /// invalidates this view directly regardless of `==`.
    nonisolated static func == (lhs: ScheduledTaskCard, rhs: ScheduledTaskCard) -> Bool {
        lhs.task == rhs.task
            && lhs.providerName == rhs.providerName
            && lhs.isRunNowPending == rhs.isRunNowPending
            && lhs.isSelected == rhs.isSelected
            && lhs.cardFocusID == rhs.cardFocusID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)

                // The card's only signal that work is in flight, now that the actions
                // live behind a glyph: the disabled Run now row is invisible until the
                // menu is open. Colorless per the status mapping in `Views/AGENTS.md` —
                // the spinning shape is the signal.
                if isRunning {
                    StatusIndicatorSpinner(color: .secondary, diameter: 12)
                        .accessibilityLabel(isRunNowPending ? "Starting" : "Running")
                }

                Spacer(minLength: 8)

                ScheduledTaskActionsMenu(
                    task: task,
                    isRunNowPending: isRunNowPending,
                    onPause: onPause,
                    onResume: onResume,
                    onRunNow: onRunNow,
                    onDelete: onDelete
                )
            }

            ScheduledTaskCardMetaLine(task: task, providerName: providerName)

            VStack(alignment: .leading, spacing: 4) {
                ScheduledTaskMetadataLabel(
                    systemImage: "repeat",
                    text: ScheduledTaskPresentationFormatting.recurrenceSummary(
                        task.recurrence,
                        timeZoneIdentifier: task.timeZoneIdentifier,
                        locale: locale
                    )
                )

                if task.isWaitingForTarget {
                    ScheduledTaskMetadataLabel(
                        systemImage: "hourglass",
                        text: "Waiting for the attached thread to become idle"
                    )
                }

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
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Paused reason: \(blockedReason)")
            }
        }
        .padding(14)
        // Height is content-driven — every text run here is line-limited, so there is no
        // fixed height to pick. `maxHeight` fills the `LazyVGrid` row instead, which keeps
        // a card carrying a blocked-reason line level with a plain one beside it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSelectableCard(
            isSelected: isSelected,
            cornerRadius: 18,
            focus: cardFocus,
            focusID: cardFocusID,
            action: onOpen
        )
        // `.contain` rather than `.ignore`: the card holds its own actions menu, and
        // collapsing it into one element would hide it from VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.title)
    }

    private var isRunning: Bool {
        isRunNowPending || task.hasActiveRun
    }
}

/// State, agent, and destination on one line. Collapsed from a badge row plus a trailing
/// provider label plus a stacked `folder` metadata row, because the card's height was the
/// whole complaint; `lineLimit(1)` keeps a long workspace summary from reflowing the card
/// at the narrow one-column width.
private struct ScheduledTaskCardMetaLine: View {
    let task: ScheduledTaskRowPresentation
    let providerName: String

    var body: some View {
        HStack(spacing: 6) {
            // Fixed so a long workspace summary truncates instead of squeezing the
            // capsule, whose background makes compression read as a rendering fault.
            ScheduledTaskStateBadge(state: task.state)
                .fixedSize()

            // One `Text`, not a separator view between two: `workspaceSummary` already
            // embeds its own inline interpuncts, and an `HStack`-spaced one beside them
            // renders visibly wider than its neighbours on the same line.
            Text("\(providerName) · \(task.workspaceSummary)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
                .lineLimit(1)
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

/// Every action the card offers. The card face itself opens the editor pane, so Edit has
/// no row here — a menu row duplicating the card's own click target is noise.
private struct ScheduledTaskActionsMenu: View {
    let task: ScheduledTaskRowPresentation
    let isRunNowPending: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onRunNow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        AppOverflowMenu(name: "Scheduled task actions") {
            AppOverflowMenuRow(
                title: runNowTitle,
                systemImage: "play.fill",
                action: onRunNow
            )
            .disabled(!task.canRunNow || isRunNowPending)

            if task.canPause {
                AppOverflowMenuRow(title: "Pause", systemImage: "pause.circle", action: onPause)
            } else if task.canResume {
                AppOverflowMenuRow(title: "Resume", systemImage: "play.circle", action: onResume)
            }

            Divider()

            AppOverflowMenuRow(
                title: "Delete",
                systemImage: "trash",
                role: .destructive,
                action: onDelete
            )
        }
    }

    /// The buttons this menu replaced explained an unavailable Run now through `.help(...)`
    /// tooltips, which menu rows do not show. The title carries the reason instead, so a
    /// disabled row is never silent about why.
    private var runNowTitle: String {
        if isRunNowPending {
            return "Starting…"
        }
        if task.isWaitingForTarget {
            return "Waiting for thread"
        }
        if task.hasActiveRun {
            return "Running…"
        }
        return "Run now"
    }
}
