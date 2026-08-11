import SwiftUI

/// The shared shape of the Overview's metadata sections — linked owners,
/// Reviewers, and Checks. All three were hand-rolled copies of one recipe, which
/// is how the Checks heading drifted to `.headline`/`.primary` while its
/// siblings stayed subtle.
enum PullRequestOverviewSectionMetrics {
    /// Gap between a section heading and its rows. Rows carry `rowVerticalInset`
    /// of their own, so the visible gap is this plus that.
    static let headerSpacing: CGFloat = 6

    /// How far a row's hover and press fill bleeds past the pane's content column
    /// on each side. `PullRequestOverviewSectionRows` pulls its stack back by
    /// exactly the negative of this, so a row's trailing edge lands back on the
    /// column and its glyph stays on `ContextualPaneLayout.trailingGlyphAxis`.
    static let rowHorizontalInset: CGFloat = 8
    static let rowVerticalInset: CGFloat = 6

    /// Gap between the Overview's top-level blocks.
    static let sectionSpacing: CGFloat = 20
}

/// A titled Overview section. The heading is the app's subtle section style,
/// matching the sidebar's `SidebarSectionHeaderRow` and the pull-request list's
/// own headings.
struct PullRequestOverviewSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PullRequestOverviewSectionMetrics.headerSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityAddTraits(.isHeader)

            content
        }
    }
}

/// The row stack inside a section. Rows carry `rowHorizontalInset` so their
/// fills read as full-width, so the stack pulls back by the same amount to put
/// row text back on the heading's leading edge — and, just as importantly, to
/// leave each row's trailing edge on the content column where the glyph lane
/// expects it. Content that is not a row (an error banner) stays outside this.
struct PullRequestOverviewSectionRows<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, -PullRequestOverviewSectionMetrics.rowHorizontalInset)
    }
}

/// The insets every section row shares, whether it is a button or plain content.
/// The full-width frame belongs here so callers can apply a background after it
/// and have the fill span the row.
private struct PullRequestOverviewRowInsets: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, PullRequestOverviewSectionMetrics.rowHorizontalInset)
            .padding(.vertical, PullRequestOverviewSectionMetrics.rowVerticalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func pullRequestOverviewRowInsets() -> some View {
        modifier(PullRequestOverviewRowInsets())
    }
}
