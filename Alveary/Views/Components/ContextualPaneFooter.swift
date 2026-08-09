import SwiftUI

enum ContextualPaneLayout {
    /// 16 points on both sides for the detail/right panes (Skills, MCP,
    /// Scheduled, Pull requests). This is also the *visible* inset: the resize
    /// lane's divider line draws flush with the pane's frame edge
    /// (`RightPaneResizeHandle` trailing-aligns it), so padding and visible
    /// inset are the same number on both sides.
    static let horizontalInset: CGFloat = 16
    static let actionSpacing: CGFloat = 12
    static let minimumHorizontalActionWidth: CGFloat = 128

    /// Width of the lane a pane's chromeless trailing glyphs center in, its outer
    /// edge on `horizontalInset`. 12 is the widest of those glyphs, so the lane is
    /// the narrowest one that holds them all without pulling the wide ones inboard.
    static let trailingGlyphLaneWidth: CGFloat = 12

    /// The vertical axis every chromeless trailing glyph centers its *ink* on,
    /// measured from the pane's trailing edge (see `contextualPaneTrailingGlyphLane`).
    static var trailingGlyphAxis: CGFloat { horizontalInset + trailingGlyphLaneWidth / 2 }

    /// How far `contextualPaneTrailingGlyphLane(controlWidth:)` pulls a control past
    /// `horizontalInset` to reach the axis. A header reserving room for one of these
    /// must measure to where the control lands, not to its untouched frame.
    static func trailingGlyphLaneOverhang(controlWidth: CGFloat) -> CGFloat {
        horizontalInset + controlWidth / 2 - trailingGlyphAxis
    }

    /// All-edges content insets for pane *scroll content*. Footers are not scroll
    /// content: they take their padding from `contextualPaneFooterChrome()`,
    /// which is the only surface allowed to decide a footer's vertical inset.
    static func contentInsets(vertical: CGFloat = 12) -> EdgeInsets {
        EdgeInsets(
            top: vertical,
            leading: horizontalInset,
            bottom: vertical,
            trailing: horizontalInset
        )
    }
}

/// The one vertical inset every bar-backed pane footer uses. Deliberately private:
/// a footer reaches it through `contextualPaneFooterChrome()` and nowhere else, so
/// a new footer cannot quietly pick its own number. Three surfaces had drifted to
/// 16 / 12 / 10 before the chrome was pulled into one modifier.
private let contextualPaneFooterVerticalPadding: CGFloat = 16

/// Applies the pane's shared horizontal insets (see `ContextualPaneLayout`).
private struct ContextualPaneHorizontalInsets: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, ContextualPaneLayout.horizontalInset)
    }
}

/// Sizes a bare trailing glyph to the lane so its ink centers on the shared axis
/// (see `contextualPaneTrailingGlyphLane`). The frame does not clip: a glyph wider
/// than the lane overhangs it symmetrically, which keeps the center where it is.
private struct ContextualPaneTrailingGlyphLane: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(width: ContextualPaneLayout.trailingGlyphLaneWidth, alignment: .center)
    }
}

/// Pulls a chromeless control outward until its frame center — and so its centered
/// glyph's ink — lands on the lane axis (see `contextualPaneTrailingGlyphLane`).
private struct ContextualPaneTrailingGlyphLaneControl: ViewModifier {
    let controlWidth: CGFloat

    func body(content: Content) -> some View {
        content.padding(
            .trailing,
            -ContextualPaneLayout.trailingGlyphLaneOverhang(controlWidth: controlWidth)
        )
    }
}

/// The full chrome of a pane footer: shared insets, the `.bar` fill, and the top
/// hairline inset to match `ContextualPaneHeader`'s bottom one.
private struct ContextualPaneFooterChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contextualPaneHorizontalInsets()
            .padding(.vertical, contextualPaneFooterVerticalPadding)
            .background(.bar)
            .overlay(alignment: .top) {
                AppSeparatorHairline(surface: .paneHeader)
                    .contextualPaneHorizontalInsets()
            }
    }
}

extension View {
    func contextualPaneHorizontalInsets() -> some View {
        modifier(ContextualPaneHorizontalInsets())
    }

    /// Wraps a pane footer's content in the shared footer chrome. Every
    /// bar-backed footer strip goes through this — hand-rolling the padding,
    /// background, or hairline is what let the surfaces diverge.
    func contextualPaneFooterChrome() -> some View {
        modifier(ContextualPaneFooterChrome())
    }

    /// Centers a bare trailing glyph's *ink* on `ContextualPaneLayout.trailingGlyphAxis`,
    /// the one axis every chromeless glyph down the pane's trailing edge shares.
    ///
    /// These glyphs are sparse and far apart vertically, so the eye reads each one's
    /// mass rather than a right rule — and right-aligning ink scatters the centers,
    /// because SF Symbols of one point size differ in width (a 5.5pt chevron landed
    /// 2.8pt off a 12pt bubble beside it). The lane is fixed-width so width stops
    /// mattering. Text — timestamps, diff stats — stays right-aligned on the content
    /// column instead; a ragged right edge down a run of them reads worse.
    func contextualPaneTrailingGlyphLane() -> some View {
        modifier(ContextualPaneTrailingGlyphLane())
    }

    /// Puts a chromeless *control* on the same axis by pulling its frame outward,
    /// for a glyph centered in a hit target wider than the lane (a 30pt icon button).
    /// The hit target overhangs the pane inset, which is fine because these draw
    /// nothing until hover. Chrome *outside* a scroll view only — an interactive
    /// control inside one still owes `AppScrollIndicatorLayout.interactiveTrailingClearance`.
    func contextualPaneTrailingGlyphLane(controlWidth: CGFloat) -> some View {
        modifier(ContextualPaneTrailingGlyphLaneControl(controlWidth: controlWidth))
    }
}

struct ContextualPaneFooter<LeadingAction: View, TrailingAction: View, Note: View>: View {
    @ViewBuilder let note: () -> Note
    @ViewBuilder let leadingAction: () -> LeadingAction
    @ViewBuilder let trailingAction: () -> TrailingAction

    init(
        @ViewBuilder note: @escaping () -> Note,
        @ViewBuilder leadingAction: @escaping () -> LeadingAction,
        @ViewBuilder trailingAction: @escaping () -> TrailingAction
    ) {
        self.note = note
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            note()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ContextualPaneLayout.actionSpacing) {
                    leadingAction()
                        .frame(
                            minWidth: ContextualPaneLayout.minimumHorizontalActionWidth,
                            maxWidth: .infinity
                        )
                    trailingAction()
                        .frame(
                            minWidth: ContextualPaneLayout.minimumHorizontalActionWidth,
                            maxWidth: .infinity
                        )
                }

                VStack(spacing: 10) {
                    trailingAction()
                        .frame(maxWidth: .infinity)
                    leadingAction()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .contextualPaneFooterChrome()
    }
}

extension ContextualPaneFooter where Note == EmptyView {
    init(
        @ViewBuilder leadingAction: @escaping () -> LeadingAction,
        @ViewBuilder trailingAction: @escaping () -> TrailingAction
    ) {
        self.init(
            note: { EmptyView() },
            leadingAction: leadingAction,
            trailingAction: trailingAction
        )
    }
}
