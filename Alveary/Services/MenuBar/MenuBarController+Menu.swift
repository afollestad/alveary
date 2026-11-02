@preconcurrency import AppKit
import SwiftUI

/// The status menu's contents and actions.
///
/// The menu is rebuilt in `menuNeedsUpdate(_:)` rather than kept in sync with the store: it is
/// only visible while the user holds it open, so a click-time query costs nothing and needs no
/// thread observers.
extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    /// Rows past this collapse into one "N More…" item, so a long review queue cannot push the
    /// recent threads and commands off the bottom of the screen.
    static let maxListedPullRequests = 10

    func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        if reviewRequestsMonitor.phase != .inactive {
            addPullRequestsNeedingReview(to: menu)
            menu.addItem(.separator())
        }

        menu.addItem(.sectionHeader(title: "Recent threads"))
        let recentThreads = recentThreadsProvider.recentThreads()
        if recentThreads.isEmpty {
            menu.addItem(placeholderItem(title: "No Recent Threads"))
        } else {
            for thread in recentThreads {
                let item = NSMenuItem(title: thread.title, action: #selector(openRecentThread(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = thread.conversationID
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(commandItem(title: "New Thread", action: #selector(newThread), shortcut: .newThread))
        menu.addItem(commandItem(title: "Open Alveary", action: #selector(openAlveary), shortcut: nil))
        menu.addItem(commandItem(title: "Settings...", action: #selector(openSettings), shortcut: .settings))
        menu.addItem(.separator())
        // ⌘Q is the system-standard quit equivalent, not an app-defined binding.
        let quitItem = NSMenuItem(title: "Quit Alveary", action: #selector(quitAlveary), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Rows read the monitor's last good list, so a failed refresh keeps showing them; only a
    /// section that has never loaded says it is loading or failed.
    private func addPullRequestsNeedingReview(to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Needs review"))
        let summaries = reviewRequestsMonitor.visibleSummaries
        guard !summaries.isEmpty else {
            menu.addItem(placeholderItem(title: Self.pullRequestsPlaceholderTitle(for: reviewRequestsMonitor.phase)))
            return
        }
        for summary in summaries.prefix(Self.maxListedPullRequests) {
            let item = NSMenuItem(
                title: MenuBarItemTitle.truncated(summary.title),
                action: #selector(openPullRequest(_:)),
                keyEquivalent: ""
            )
            item.subtitle = summary.id.displayKey
            item.target = self
            item.representedObject = summary
            menu.addItem(item)
        }
        let overflow = summaries.count - Self.maxListedPullRequests
        if overflow > 0 {
            let item = NSMenuItem(title: "\(overflow) More…", action: #selector(showPullRequestsNeedingReview), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    private static func pullRequestsPlaceholderTitle(for phase: MenuBarReviewRequestsMonitor.Phase) -> String {
        switch phase {
        case .inactive, .loading:
            return "Loading…"
        case .loaded:
            return "No Pull Requests"
        case .failed:
            return "Couldn't Load Pull Requests"
        }
    }

    /// A nil action is what greys it out; the menu still auto-enables everything else.
    private func placeholderItem(title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func commandItem(title: String, action: Selector, shortcut: KeyboardShortcut?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut {
            MenuBarKeyEquivalent.apply(shortcut, to: item)
        }
        return item
    }

    @objc
    private func openRecentThread(_ sender: NSMenuItem) {
        guard let conversationID = sender.representedObject as? String else {
            return
        }
        mainWindowPresenter.activate()
        notificationRouter.requestOpen(conversationId: conversationID)
    }

    @objc
    private func openPullRequest(_ sender: NSMenuItem) {
        guard let summary = sender.representedObject as? PullRequestSummary else {
            return
        }
        mainWindowPresenter.activate()
        commandRouter.requestOpenPullRequest(summary)
    }

    @objc
    private func showPullRequestsNeedingReview() {
        mainWindowPresenter.activate()
        commandRouter.requestShowPullRequestsNeedingReview()
    }

    @objc
    private func newThread() {
        mainWindowPresenter.activate()
        commandRouter.requestNewThread()
    }

    @objc
    private func openAlveary() {
        mainWindowPresenter.activate()
    }

    @objc
    private func openSettings() {
        mainWindowPresenter.activate()
        commandRouter.requestOpenSettings()
    }

    @objc
    private func quitAlveary() {
        terminate()
    }
}
