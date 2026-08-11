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
