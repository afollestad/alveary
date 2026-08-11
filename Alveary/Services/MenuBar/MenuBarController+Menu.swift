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

    func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let recentThreads = recentThreadsProvider.recentThreads()
        if recentThreads.isEmpty {
            // A nil action is what greys it out; the menu still auto-enables everything else.
            menu.addItem(NSMenuItem(title: "No Recent Threads", action: nil, keyEquivalent: ""))
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
