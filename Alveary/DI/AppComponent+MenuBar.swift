import AppKit
import Foundation
import SwiftData

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

    var menuBarReviewRequestsMonitor: MenuBarReviewRequestsMonitor {
        return shared {
            // Hosted tests start the real status item, and a poll there would run `gh` against
            // the developer's account; the monitor's lifecycle still runs, only the reads stop.
            MenuBarReviewRequestsMonitor(
                service: pullRequestsService,
                ignoreService: pullRequestIgnoreService,
                agentReviews: MenuBarAgentReviewHandoffs(
                    activity: pullRequestAgenticThreadActivity,
                    // A fresh context per read, as `PullRequestReviewProposalCoordinator.reload()`
                    // does: proposals are written from several contexts, and a reused one could
                    // answer with an envelope it cached before another context cleared it.
                    pendingProposalIdentifiers: { [modelContainer] in
                        let conversations = (try? ModelContext(modelContainer).fetch(
                            PullRequestReviewProposalLookup.proposalHoldingConversations
                        )) ?? []
                        return Set(PullRequestReviewProposalLookup.proposals(in: conversations).compactMap(\.record.identifier))
                    }
                ),
                listCache: pullRequestsListCache,
                pollsGitHub: !AppRuntimeProfile.current.isHostedUnitTest
            )
        }
    }

    var menuBarController: MenuBarController {
        return shared {
            // App-hosted unit tests run the real lifecycle, so the controller installs and
            // uninstalls for real; only the visible chrome is suppressed, the same way
            // `.defaultLaunchBehavior(.suppressed)` suppresses the window.
            let isHostedUnitTest = AppRuntimeProfile.current.isHostedUnitTest
            return MenuBarController(
                recentThreadsProvider: menuBarRecentThreadsProvider,
                reviewRequestsMonitor: menuBarReviewRequestsMonitor,
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
