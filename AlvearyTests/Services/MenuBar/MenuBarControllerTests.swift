import AppKit
import Foundation
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testInstallsWhileTheSettingIsOnAndRemovesWhenItGoesOff() throws {
        let fixture = try makeFixture()
        let controller = fixture.makeController()

        controller.start()

        XCTAssertTrue(controller.isInstalled)
        XCTAssertEqual(fixture.statusItemFactory.madeItems.count, 1)

        fixture.settingsService.update { $0.showsMenuBarIcon = false }
        controller.applySettings()

        XCTAssertFalse(controller.isInstalled)
        XCTAssertEqual(fixture.statusItemFactory.removedItems.count, 1)

        fixture.settingsService.update { $0.showsMenuBarIcon = true }
        controller.applySettings()

        XCTAssertTrue(controller.isInstalled)
        XCTAssertEqual(fixture.statusItemFactory.madeItems.count, 2)
    }

    func testStaysUninstalledWhileTheSettingIsOff() throws {
        var settings = AppSettings()
        settings.showsMenuBarIcon = false
        let fixture = try makeFixture(settings: settings)
        let controller = fixture.makeController()

        controller.start()

        XCTAssertFalse(controller.isInstalled)
        XCTAssertTrue(fixture.statusItemFactory.madeItems.isEmpty)
    }

    func testStopRemovesTheStatusItem() throws {
        let fixture = try makeFixture()
        let controller = fixture.makeController()
        controller.start()

        controller.stop()

        XCTAssertFalse(controller.isInstalled)
        XCTAssertEqual(fixture.statusItemFactory.removedItems.count, 1)
    }

    func testMenuListsRecentThreadsAboveTheCommands() throws {
        let fixture = try makeFixture()
        fixture.insertThread(name: "Newest", conversationID: "convo-newest", modifiedAt: fixture.date(-1))
        fixture.insertThread(name: "Older", conversationID: "convo-older", modifiedAt: fixture.date(-50))
        let menu = NSMenu()
        // Held: `NSMenuItem.target` is weak, so a temporary controller would leave dead actions.
        let controller = fixture.makeController()
        controller.rebuild(menu)

        XCTAssertEqual(
            menu.items.map(\.title),
            ["Newest", "Older", "", "New Thread", "Open Alveary", "Settings...", "", "Quit Alveary"]
        )
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertTrue(menu.items[6].isSeparatorItem)
        XCTAssertEqual(menu.items[0].representedObject as? String, "convo-newest")
    }

    func testMenuShowsADisabledPlaceholderWithoutRecentThreads() throws {
        let fixture = try makeFixture()
        let menu = NSMenu()
        let controller = fixture.makeController()
        controller.rebuild(menu)

        XCTAssertEqual(menu.items.first?.title, "No Recent Threads")
        XCTAssertNil(menu.items.first?.action)
    }

    func testCommandKeyEquivalentsFollowTheAppShortcuts() throws {
        let fixture = try makeFixture()
        let menu = NSMenu()
        let controller = fixture.makeController()
        controller.rebuild(menu)

        let newThread = try XCTUnwrap(menu.items.first { $0.title == "New Thread" })
        XCTAssertEqual(newThread.keyEquivalent, String(KeyboardShortcut.newThread.key.character))
        XCTAssertEqual(newThread.keyEquivalentModifierMask, .command)

        let settings = try XCTUnwrap(menu.items.first { $0.title == "Settings..." })
        XCTAssertEqual(settings.keyEquivalent, String(KeyboardShortcut.settings.key.character))
        XCTAssertEqual(settings.keyEquivalentModifierMask, .command)
    }

    func testPickingARecentThreadRoutesItsConversation() throws {
        let fixture = try makeFixture()
        fixture.insertThread(name: "Newest", conversationID: "convo-newest", modifiedAt: fixture.date(-1))
        let menu = NSMenu()
        let controller = fixture.makeController()
        controller.rebuild(menu)

        menu.performActionForItem(at: 0)

        XCTAssertEqual(fixture.notificationRouter.pendingConversationId, "convo-newest")
    }

    func testCommandItemsEnqueueOnTheCommandRouter() throws {
        let fixture = try makeFixture()
        let menu = NSMenu()
        let controller = fixture.makeController()
        controller.rebuild(menu)

        try performItem(titled: "New Thread", in: menu)
        XCTAssertEqual(fixture.commandRouter.pendingCommand?.kind, .newThread)

        try performItem(titled: "Settings...", in: menu)
        XCTAssertEqual(fixture.commandRouter.pendingCommand?.kind, .openSettings)
    }

    func testOpenAlvearyOnlyRevealsTheApp() throws {
        let fixture = try makeFixture()
        let menu = NSMenu()
        let controller = fixture.makeController()
        controller.rebuild(menu)

        try performItem(titled: "Open Alveary", in: menu)

        XCTAssertNil(fixture.commandRouter.pendingCommand)
        XCTAssertNil(fixture.notificationRouter.pendingConversationId)
    }

    func testQuitTerminatesTheApp() throws {
        let fixture = try makeFixture()
        let menu = NSMenu()
        let controller = fixture.makeController()
        controller.rebuild(menu)

        try performItem(titled: "Quit Alveary", in: menu)

        XCTAssertEqual(fixture.terminateCount.count, 1)
    }

    private func performItem(titled title: String, in menu: NSMenu) throws {
        let index = try XCTUnwrap(menu.items.firstIndex { $0.title == title })
        menu.performActionForItem(at: index)
    }

    private func makeFixture(settings: AppSettings = AppSettings()) throws -> MenuBarControllerTestFixture {
        try MenuBarControllerTestFixture(settings: settings)
    }
}
