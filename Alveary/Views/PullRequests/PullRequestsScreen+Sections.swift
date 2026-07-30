import SwiftUI

/// The list body: sections from `visibleSections(for:)` with subtle sidebar-style
/// headings ("Authored", "Pending review", "Previously reviewed").
struct PullRequestsSectionedList: View {
    let sections: [PullRequestListSection]
    let showsRepository: Bool
    let referenceDate: Date
    let avatarLoader: GitHubAvatarLoader
    let isSelected: (PullRequestIdentifier) -> Bool
    let onSelect: (PullRequestSummary) -> Void

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
                        isSelected: isSelected(summary.id),
                        referenceDate: referenceDate,
                        avatarLoader: avatarLoader,
                        onSelect: { onSelect(summary) }
                    )
                }
            }
        }
    }
}
