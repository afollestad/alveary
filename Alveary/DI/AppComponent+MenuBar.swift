import AppKit
import Foundation

@MainActor
extension AppComponent {
    var mainWindowPresenter: MainWindowPresenter {
        return shared { MainWindowPresenter() }
    }

    var menuBarCommandRouter: MenuBarCommandRouter {
        return shared { MenuBarCommandRouter() }
    }

    var menuBarRecentThreadsProvider: MenuBarRecentThreadsProvider {
        // `mainContext`, not the shared secondary `modelContext`: menu reads must see UI writes,
        // or a renamed thread keeps its old title here until relaunch.
        return shared { MenuBarRecentThreadsProvider(modelContext: modelContainer.mainContext) }
    }

    var menuBarController: MenuBarController {
        return shared {
            // App-hosted unit tests run the real lifecycle, so the controller installs and
            // uninstalls for real; only the visible chrome is suppressed, the same way
            // `.defaultLaunchBehavior(.suppressed)` suppresses the window.
            let isHostedUnitTest = AppRuntimeProfile.current.isHostedUnitTest
            return MenuBarController(
                recentThreadsProvider: menuBarRecentThreadsProvider,
                notificationRouter: notificationRouter,
                commandRouter: menuBarCommandRouter,
                mainWindowPresenter: mainWindowPresenter,
                settingsService: settingsService,
                makeStatusItem: {
                    isHostedUnitTest
                        ? NSStatusItem()
                        : NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                },
                removeStatusItem: { statusItem in
                    guard !isHostedUnitTest else {
                        return
                    }
                    NSStatusBar.system.removeStatusItem(statusItem)
                }
            )
        }
    }
}
