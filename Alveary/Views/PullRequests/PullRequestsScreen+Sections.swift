import SwiftUI

/// The list body: sections from `visibleSections(for:)` with subtle sidebar-style
/// headings ("Authored", "Pending review", "Previously reviewed").
struct PullRequestsSectionedList: View, Equatable {
    let sections: [PullRequestListSection]
    let showsRepository: Bool
    let referenceDate: Date
    let avatarLoader: GitHubAvatarLoader
    /// The open detail, not an `isSelected` closure: a closure is never equal to the one
    /// from the previous pass, so every row would rebuild on every render.
    let activeDetailID: PullRequestIdentifier?
    let onSelect: (PullRequestSummary) -> Void

    /// Skips rebuilding every row value during the right pane's slide-in, whose geometry
    /// changes re-run the enclosing `GeometryReader` closure per frame. `onSelect` is
    /// excluded like the row's own action: it captures the view model reference and the
    /// screen's `@FocusState` storage, neither of which a render pass can change.
    nonisolated static func == (lhs: PullRequestsSectionedList, rhs: PullRequestsSectionedList) -> Bool {
        lhs.sections == rhs.sections
            && lhs.showsRepository == rhs.showsRepository
            && lhs.referenceDate == rhs.referenceDate
            && lhs.activeDetailID == rhs.activeDetailID
            && lhs.avatarLoader === rhs.avatarLoader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sections) { section in
                sectionView(section)
            }
        }
    }

    private func sectionView(_ section: PullRequestListSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = section.title {
                // Matches the sidebar's subtle section headers (`SidebarSectionHeaderRow`).
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityAddTraits(.isHeader)
            }

            LazyVStack(spacing: 10) {
                ForEach(section.rows) { summary in
                    PullRequestRow(
                        summary: summary,
                        showsRepository: showsRepository,
                        isSelected: summary.id == activeDetailID,
                        referenceDate: referenceDate,
                        avatarLoader: avatarLoader,
                        onSelect: { onSelect(summary) }
                    )
                    .equatable()
                }
            }
        }
    }
}
