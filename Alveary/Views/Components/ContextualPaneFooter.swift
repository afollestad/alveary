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

    /// All-edges content insets for pane scroll content.
    static func contentInsets(vertical: CGFloat = 12) -> EdgeInsets {
        EdgeInsets(
            top: vertical,
            leading: horizontalInset,
            bottom: vertical,
            trailing: horizontalInset
        )
    }
}

/// Applies the pane's shared horizontal insets (see `ContextualPaneLayout`).
private struct ContextualPaneHorizontalInsets: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, ContextualPaneLayout.horizontalInset)
    }
}

extension View {
    func contextualPaneHorizontalInsets() -> some View {
        modifier(ContextualPaneHorizontalInsets())
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
        .contextualPaneHorizontalInsets()
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
                .contextualPaneHorizontalInsets()
        }
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
