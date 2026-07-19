import SwiftUI

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
        .padding(.leading, 20)
        .padding(.trailing, 21)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }
}
