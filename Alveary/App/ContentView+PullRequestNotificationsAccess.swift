import SwiftUI

extension ContentView {
    /// The notifications-access sheet ignoring a pull request can raise. Hosted at the root, once,
    /// because an ignore can start from the list or from a pane opened off a thread's link, with
    /// no list mounted. Lifted out of `body` for the type-check budget.
    func pullRequestNotificationsAccessSheetHost<Content: View>(_ content: Content) -> some View {
        content.sheet(isPresented: pullRequestNotificationsAccessPresented) {
            if let request = pullRequestsViewModel.ignoring.notificationsAccessRequest {
                let ignoring = pullRequestsViewModel.ignoring
                PullRequestNotificationsAccessSheet(
                    request: request,
                    onContinue: ignoring.continueNotificationsAccess,
                    onOpenBrowser: ignoring.openNotificationsAccessBrowser,
                    onCopyCode: ignoring.copyNotificationsAccessCode,
                    onRetry: ignoring.retryNotificationsAccess,
                    onCancel: ignoring.cancelNotificationsAccess
                )
                .equatable()
            }
        }
    }

    /// Dismissing the sheet any other way than its own buttons is a Cancel.
    private var pullRequestNotificationsAccessPresented: Binding<Bool> {
        Binding(
            get: { pullRequestsViewModel.ignoring.notificationsAccessRequest != nil },
            set: { isPresented in
                if !isPresented {
                    pullRequestsViewModel.ignoring.cancelNotificationsAccess()
                }
            }
        )
    }
}
