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
///
/// The `accessory` slot carries a control on the heading's trailing edge; the
/// Description section's Edit menu is the one user, since the description has no
/// author row of its own to ride. It lands on the pane's trailing glyph lane, so
/// an interactive accessory owes `contextualPaneTrailingGlyphLane(controlWidth:)`
/// at the call site — the slot cannot know the control's hit width.
struct PullRequestOverviewSection<Content: View, Accessory: View>: View {
    private let title: String
    private let content: Content
    private let accessory: Accessory

    init(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PullRequestOverviewSectionMetrics.headerSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The accessory overlays the heading rather than sharing a stack with
                // it, because a control's hit target is taller than the heading text
                // and would otherwise pad the row — leaving a section's spacing to
                // depend on whether the viewer happens to have an accessory at all.
                // It draws nothing until hover, so the overhang costs nothing.
                .overlay(alignment: .trailing) { accessory }

            content
        }
    }
}

extension PullRequestOverviewSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// The row stack inside a section. Rows carry `rowHorizontalInset` so their
/// fills read as full-width, so the stack pulls back by the same amount to put
/// row text back on the heading's leading edge — and, just as importantly, to
/// leave each row's trailing edge on the content column where the glyph lane
/// expects it. Content that is not a row (an error banner) stays outside this.
///
/// The bottom pulls back by `rowVerticalInset` for the same reason: the last
/// row's padding would otherwise stack onto `sectionSpacing`, so a section
/// following rows sat ~6pt lower than one following the header, which carries no
/// such inset. Only the bottom — pulling the top back too would tighten the
/// heading onto its first row, and the gaps *within* a section are correct.
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
        .padding(.bottom, -PullRequestOverviewSectionMetrics.rowVerticalInset)
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
