import SwiftUI

extension View {
    /// Draws the hairline that separates the pane's tab row from content scrolled under it,
    /// matching the pane header's own bottom hairline and its inset.
    ///
    /// **Applied by each tab, never by the tab row.** `KeepAliveTabContainer` keeps every visited
    /// tab mounted with its own scroll offset, so a divider owned by the row would need the
    /// deselected tab's scroll state plumbed up through views that are deliberately `Equatable`
    /// with their closures excluded, and it would still lag a switch by a frame. A hidden tab is
    /// fully transparent, so only the selected tab's hairline is ever visible — which is what makes
    /// the divider re-decide itself on a tab switch, for free.
    func pullRequestPaneTabDivider(isScrolled: Bool) -> some View {
        modifier(PullRequestPaneTabDivider(isScrolled: isScrolled))
    }

    /// Tracks whether this scroll view has left its top edge, for a tab that owns the scroll view
    /// it draws ``pullRequestPaneTabDivider(isScrolled:)`` from. A tab whose scroll view belongs to
    /// a shared child — the Changes tab's `FlattenedDiffPreview` — takes the reading from that
    /// child's own report instead.
    func pullRequestPaneScrolledFromTop(_ isScrolled: Binding<Bool>) -> some View {
        modifier(PullRequestPaneScrolledFromTop(isScrolled: isScrolled))
    }
}

/// An overlay rather than a hairline stacked above the content: it adds no layout, so the divider
/// appearing cannot nudge the rows it is meant to separate, and it paints over the content passing
/// beneath it. `AppSeparatorHairline` is already non-hit-testing and accessibility-hidden.
private struct PullRequestPaneTabDivider: ViewModifier {
    let isScrolled: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isScrolled {
                AppSeparatorHairline(surface: .paneHeader)
                    .contextualPaneHorizontalInsets()
            }
        }
    }
}

/// Transforms the geometry to a `Bool` so the action runs on the crossing rather than on every
/// scroll frame; `ScrollGeometry.isScrolledFromTop` owns the threshold both tabs share.
private struct PullRequestPaneScrolledFromTop: ViewModifier {
    @Binding var isScrolled: Bool

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.isScrolledFromTop
        } action: { _, newValue in
            isScrolled = newValue
        }
    }
}
