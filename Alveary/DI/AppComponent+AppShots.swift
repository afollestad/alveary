import Foundation

@MainActor
extension AppComponent {
    /// App-scoped rather than window-scoped: it registers the global capture shortcut, which has
    /// to outlive the window now that closing the window no longer quits the app.
    var appShotCoordinator: AppShotCoordinator {
        return shared {
            AppShotCoordinator(
                // Hosted tests run the real lifecycle, but the shortcut is registered with the
                // system: a test run would take ⌃⇧S away from the developer's own Alveary for
                // its whole duration. Suppress only that, as the status item suppresses only
                // its chrome.
                installsGlobalShortcut: !AppRuntimeProfile.current.isHostedUnitTest,
                presentMainWindowIfClosed: { [mainWindowPresenter] in
                    mainWindowPresenter.activateIfWindowClosed()
                }
            )
        }
    }
}
