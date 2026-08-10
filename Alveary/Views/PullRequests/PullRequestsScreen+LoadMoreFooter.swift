import SwiftUI

/// The list's "Load more" footer, imitating the Changes tab's `showMoreFooter`.
///
/// Its own `Equatable` view rather than a group inside `listContent`: that body is resolved per
/// geometry frame, and keeping the footer's own inputs comparable stops a resize from rebuilding
/// it — the same reason `PullRequestsSectionedList` is equatable. `onLoadMore` is excluded from
/// `==` because it captures only the root-lived view model.
struct PullRequestsLoadMoreFooter: View, Equatable {
    let isLoading: Bool
    let onLoadMore: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: onLoadMore) {
                if isLoading {
                    StatusIndicatorSpinner(color: .secondary, diameter: 14, lineWidth: 2)
                } else {
                    ActionButtonLabel(title: "Load more pull requests", icon: .system("chevron.down"))
                }
            }
            .secondaryActionButtonStyle()
            .controlSize(.small)
            .disabled(isLoading)
            .help("Fetch the next page of pull requests")
            .accessibilityLabel("Load more pull requests")

            Spacer(minLength: 0)
        }
    }

    nonisolated static func == (lhs: PullRequestsLoadMoreFooter, rhs: PullRequestsLoadMoreFooter) -> Bool {
        lhs.isLoading == rhs.isLoading
    }
}
