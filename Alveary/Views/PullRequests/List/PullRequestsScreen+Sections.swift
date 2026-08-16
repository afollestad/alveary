import SwiftUI

/// The list body: one lazy column of `visibleListItems(for:)` — subtle sidebar-style headings
/// ("Authored", "Pending review", "Previously reviewed") interleaved with their rows.
///
/// A single `LazyVStack` rather than one per section inside a `VStack`: that outer stack had to
/// size every section, including ones entirely below the fold, so laziness never spanned the whole
/// scroll content.
struct PullRequestsSectionedList: View, Equatable {
    let items: [PullRequestListItem]
    let avatarLoader: GitHubAvatarLoader
    /// The open detail, not an `isSelected` closure: a closure is never equal to the one
    /// from the previous pass, so every row would rebuild on every render.
    let activeDetailID: PullRequestIdentifier?
    let onSelect: (PullRequestSummary) -> Void

    /// Skips rebuilding every row value during the right pane's slide-in, whose geometry
    /// changes re-run the enclosing `GeometryReader` closure per frame. `onSelect` is
    /// excluded like the row's own action: it captures the view model reference and the
    /// screen's `@FocusState` storage, neither of which a render pass can change.
    ///
    /// `items` carries each row's rendered strings, so the display inputs behind them —
    /// `showsRepository` and `referenceDate` — need no separate comparison here.
    nonisolated static func == (lhs: PullRequestsSectionedList, rhs: PullRequestsSectionedList) -> Bool {
        lhs.items == rhs.items
            && lhs.activeDetailID == rhs.activeDetailID
            && lhs.avatarLoader === rhs.avatarLoader
    }

    var body: some View {
        // Spacing is per item rather than on the stack: one column now carries two gaps.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                itemView(item)
                    .padding(.top, leadingSpacing(at: index))
            }
        }
    }

    /// A heading opens a new section 24pt below the previous one; rows sit 10pt apart, including
    /// the first row under a heading. Reproduces the nested stacks' `spacing: 24` and `spacing: 10`
    /// exactly.
    ///
    /// Reading the item's own kind is enough because an *untitled* section is only ever a whole
    /// tab on its own — `buildSections` gives only the Authored tab one, flat and unheaded — so no
    /// row here can be the start of a section that a heading did not already space.
    private func leadingSpacing(at index: Int) -> CGFloat {
        guard index > 0 else {
            return 0
        }
        if case .header = items[index] {
            return 24
        }
        return 10
    }

    @ViewBuilder
    private func itemView(_ item: PullRequestListItem) -> some View {
        switch item {
        case .header(_, let title):
            // Matches the sidebar's subtle section headers (`SidebarSectionHeaderRow`).
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityAddTraits(.isHeader)

        case .row(let model):
            PullRequestRow(
                model: model,
                isSelected: model.id == activeDetailID,
                avatarLoader: avatarLoader,
                onSelect: { onSelect(model.summary) }
            )
            .equatable()
            // The `ScrollViewReader` target for arrow-key selection, which scrolls by
            // `PullRequestIdentifier`. The `ForEach` identifies items by their string id, so
            // without this the identifier matches nothing and the selection scrolls nowhere.
            .id(model.id)
        }
    }
}
