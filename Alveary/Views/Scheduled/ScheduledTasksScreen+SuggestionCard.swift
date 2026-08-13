import SwiftUI

/// One starting point in the Scheduled empty state. Clicking it opens the create pane
/// pre-filled; nothing is saved until the user confirms there.
struct ScheduledTaskSuggestionCard: View, Equatable {
    let suggestion: ScheduledTaskSuggestion
    let onSelect: () -> Void
    let cardFocus: FocusState<String?>.Binding
    let cardFocusID: String

    /// `onSelect` and the focus binding are excluded: the action closes over the
    /// `suggestion` compared here plus the screen's view-model reference, and the binding
    /// reads the screen's `@FocusState` storage — neither can be staler in a captured copy
    /// than in a fresh one. The card renders inside the screen's `GeometryReader`, so this
    /// is what keeps a resize from rebuilding every card per frame.
    nonisolated static func == (lhs: ScheduledTaskSuggestionCard, rhs: ScheduledTaskSuggestionCard) -> Bool {
        lhs.suggestion == rhs.suggestion && lhs.cardFocusID == rhs.cardFocusID
    }

    var body: some View {
        HStack(spacing: 12) {
            ActionIconImage(icon: suggestion.icon, octiconSize: 16)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(suggestion.scheduleCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appOutlinedCard(
            cornerRadius: 12,
            focus: cardFocus,
            focusID: cardFocusID,
            action: onSelect
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.title), \(suggestion.scheduleCaption)")
    }
}
