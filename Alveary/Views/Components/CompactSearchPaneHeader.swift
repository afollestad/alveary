import SwiftUI

enum PaneHeaderLayout {
    static let height: CGFloat = 64

    /// Horizontal insets shared by pane headers and the scroll content beneath them.
    /// Screen content must reuse these rather than hardcoding its own padding: the
    /// header's actions and the content's rows sit against the same visual edges, so
    /// any divergence reads as a misaligned right or left margin.
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 21
}

struct CompactSearchPaneHeader<Actions: View>: View {
    @Binding private var searchQuery: String

    private let placeholder: String
    private let actions: Actions

    init(
        _ placeholder: String,
        searchQuery: Binding<String>,
        @ViewBuilder actions: () -> Actions
    ) {
        self.placeholder = placeholder
        self._searchQuery = searchQuery
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 0) {
            AppTextField(placeholder, text: $searchQuery)
                .frame(maxWidth: 360)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                actions
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, PaneHeaderLayout.leadingInset)
        .padding(.trailing, PaneHeaderLayout.trailingInset)
        .padding(.vertical, 14)
        .frame(height: PaneHeaderLayout.height)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }
}
