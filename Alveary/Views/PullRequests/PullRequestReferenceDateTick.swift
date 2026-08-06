import SwiftUI

extension View {
    /// Keeps `PullRequestsViewModel.referenceDate` moving while this surface is on screen.
    ///
    /// The value is stored rather than read from the clock on every access — every list row
    /// carries it, and a fresh `Date` per read made each row's inputs differ on every render
    /// pass — so relative ages would otherwise sit at whatever the last data landing set.
    /// Both surfaces that render ages need it: the list, and a pane opened from a thread's
    /// linked pull requests with the screen unmounted.
    ///
    /// Ages are minute-granular, so this ticks at that resolution and no faster, and
    /// `touchReferenceDate()` publishes nothing under the fixed clock snapshots inject.
    func pullRequestReferenceDateTick(_ viewModel: PullRequestsViewModel) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else {
                    return
                }
                viewModel.touchReferenceDate()
            }
        }
    }
}
