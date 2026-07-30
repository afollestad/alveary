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
