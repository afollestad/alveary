import SwiftUI

enum ContextualPaneLayout {
    static let horizontalInset: CGFloat = 12
    static let actionSpacing: CGFloat = 12
    static let minimumHorizontalActionWidth: CGFloat = 128
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
        .padding(.horizontal, ContextualPaneLayout.horizontalInset)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
                .padding(.horizontal, ContextualPaneLayout.horizontalInset)
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
