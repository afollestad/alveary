import SwiftUI

private struct DiffPreviewMinimumContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var diffPreviewMinimumContentWidth: CGFloat {
        get { self[DiffPreviewMinimumContentWidthKey.self] }
        set { self[DiffPreviewMinimumContentWidthKey.self] = newValue }
    }
}

private struct DiffPreviewViewportContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The scroll container's visible content width (viewport minus padding), for
    /// rows that must fit the pane instead of the horizontally scrollable width.
    var diffPreviewViewportContentWidth: CGFloat {
        get { self[DiffPreviewViewportContentWidthKey.self] }
        set { self[DiffPreviewViewportContentWidthKey.self] = newValue }
    }
}

/// Publishes the scroll container's horizontal content offset so viewport-fitted
/// rows can pin to the pane's leading edge instead of traveling with the diff.
/// A reference type on purpose: per-frame scroll writes must invalidate only the
/// rows that read `horizontal`, not the container body holding the row stream.
@Observable
final class DiffPreviewScrollOffset {
    var horizontal: CGFloat = 0
}

private struct DiffPreviewMinimumContentWidthModifier: ViewModifier {
    @Environment(\.diffPreviewMinimumContentWidth) private var minimumContentWidth

    func body(content: Content) -> some View {
        content.frame(minWidth: max(minimumContentWidth, 0), alignment: .leading)
    }
}

/// Fits a row to the visible pane rather than the horizontally scrollable diff
/// width. Kept separate from `DiffCommentRowWidthModifier`, which does the same
/// thing with a bounded fallback suited to an unmeasured composer; a header
/// instead wants to fill whatever width it is handed.
private struct DiffPreviewViewportContentWidthModifier: ViewModifier {
    /// Extra width past the viewport, so a trailing glyph can reach a column
    /// outside the diff's own content inset. Widening the *frame* rather than
    /// padding the glyph is what keeps the row's hit rect under it.
    let trailingExtension: CGFloat

    @Environment(\.diffPreviewViewportContentWidth) private var viewportContentWidth

    func body(content: Content) -> some View {
        // The scroll container proposes nil width in its scroll axes, so a row
        // without an exact frame reports its untruncated ideal and widens the
        // diff even when it contributes no scrollable width.
        if viewportContentWidth > 0 {
            content.frame(width: viewportContentWidth + trailingExtension, alignment: .leading)
        } else {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pins a viewport-fitted row to the pane's leading edge by compensating the
/// horizontal scroll offset, so the row stays fully visible while the diff
/// scrolls sideways beneath it.
private struct DiffPreviewViewportPinnedModifier: ViewModifier {
    @Environment(DiffPreviewScrollOffset.self) private var scrollOffset: DiffPreviewScrollOffset?

    func body(content: Content) -> some View {
        // Negative offsets are the left rubber-band, where the row should
        // bounce with the content instead of detaching from its leading edge.
        content.offset(x: max(scrollOffset?.horizontal ?? 0, 0))
    }
}

extension View {
    func diffPreviewMinimumContentWidthFrame() -> some View {
        modifier(DiffPreviewMinimumContentWidthModifier())
    }

    func diffPreviewViewportContentWidthFrame(trailingExtension: CGFloat = 0) -> some View {
        modifier(DiffPreviewViewportContentWidthModifier(trailingExtension: trailingExtension))
    }

    func diffPreviewViewportPinned() -> some View {
        modifier(DiffPreviewViewportPinnedModifier())
    }

    func diffPreviewIntrinsicMinimumContentWidthFrame() -> some View {
        fixedSize(horizontal: true, vertical: false)
            .diffPreviewMinimumContentWidthFrame()
    }
}

struct DiffPreviewScrollContainer<Content: View>: View {
    private let horizontalContentPadding: CGFloat
    private let topContentPadding: CGFloat = DiffViewerPaneMetrics.diffPreviewTopInset
    private let bottomContentPadding: CGFloat = DiffViewerPaneMetrics.diffPreviewBottomInset
    private let minimumScrollableContentWidth: CGFloat

    // Written per scroll frame from `onScrollGeometryChange`; a reference type
    // so the writes invalidate only the pinned rows reading it, never this body.
    @State private var scrollOffset = DiffPreviewScrollOffset()

    @ViewBuilder private let content: () -> Content

    init(
        minimumScrollableContentWidth: CGFloat = 0,
        horizontalContentPadding: CGFloat = DiffViewerPaneMetrics.diffPreviewHorizontalInset,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minimumScrollableContentWidth = minimumScrollableContentWidth
        self.horizontalContentPadding = horizontalContentPadding
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width - (horizontalContentPadding * 2), 0)
            let availableHeight = max(proxy.size.height - topContentPadding - bottomContentPadding, 0)
            let contentWidth = max(availableWidth, minimumScrollableContentWidth)

            ScrollView([.horizontal, .vertical]) {
                content()
                    .frame(
                        minWidth: contentWidth,
                        minHeight: availableHeight,
                        alignment: .topLeading
                    )
                    .environment(\.diffPreviewMinimumContentWidth, contentWidth)
                    .environment(\.diffPreviewViewportContentWidth, availableWidth)
                    .environment(scrollOffset)
                    .padding(.horizontal, horizontalContentPadding)
                    .padding(.top, topContentPadding)
                    .padding(.bottom, bottomContentPadding)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offset in
                scrollOffset.horizontal = offset
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
