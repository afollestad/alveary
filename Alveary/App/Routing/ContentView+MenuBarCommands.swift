import Foundation

/// Drains status-menu picks that need `AppState`, which `MenuBarController` cannot reach.
///
/// Routed like the notification cases: through `performAppNavigationIfModelPreparationModalAbsent`
/// so a voice-model preparation modal keeps the request pending instead of navigating behind it.
extension ContentView {
    func routePendingMenuBarCommandIfModelPreparationAllows(_ request: MenuBarCommandRequest?) {
        guard let request else {
            return
        }
        performAppNavigationIfModelPreparationModalAbsent(
            lifecycleController: voiceInputLifecycleController
        ) {
            switch request.kind {
            case .newThread:
                appState.startNewThreadFlow()
            case .openSettings:
                appState.openSettings()
            case .openPullRequest(let summary):
                openMenuBarPullRequestInAppState(
                    summary,
                    pullRequestsEnabled: settingsService.current.pullRequestsEnabled,
                    appState: appState,
                    viewModel: pullRequestsViewModel
                )
            case .showPullRequestsNeedingReview:
                showPullRequestsNeedingReviewInAppState(
                    pullRequestsEnabled: settingsService.current.pullRequestsEnabled,
                    appState: appState,
                    viewModel: pullRequestsViewModel
                )
            }
            menuBarCommandRouter.clearPendingIfMatches(request)
        }
    }

    /// Runs a capture the coordinator raised. Clearing before the attempt matches the trigger's
    /// old semantics: a press arriving mid-capture is dropped rather than queued.
    func drainPendingAppShotCapture() {
        guard let triggerID = appShotCoordinator.pendingTriggerID else {
            return
        }
        appShotCoordinator.clearPendingTrigger(triggerID)
        appShotCaptureController.captureIfIdle()
    }
}

/// Opens a status-menu pull request on the Pull requests screen, the way tapping its row there
/// does; a `.screen` pane renders only while that screen is selected.
///
/// The menu hides its section while the integration is off, but a request queued just before the
/// user switched it off must not land on a sidebar row that no longer exists.
@MainActor
func openMenuBarPullRequestInAppState(
    _ summary: PullRequestSummary,
    pullRequestsEnabled: Bool,
    appState: AppState,
    viewModel: PullRequestsViewModel
) {
    guard pullRequestsEnabled else {
        return
    }
    appState.selectedSidebarItem = .pullRequests
    viewModel.requestDetails(summary, origin: .screen)
}

/// The menu's overflow row lands on the Reviewing tab, whose Pending review section is the full
/// list the menu truncated.
@MainActor
func showPullRequestsNeedingReviewInAppState(
    pullRequestsEnabled: Bool,
    appState: AppState,
    viewModel: PullRequestsViewModel
) {
    guard pullRequestsEnabled else {
        return
    }
    appState.selectedSidebarItem = .pullRequests
    viewModel.selectFilter(.reviewing)
}
