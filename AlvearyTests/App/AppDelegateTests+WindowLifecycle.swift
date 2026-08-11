import AppKit
import XCTest

@testable import Alveary

/// The app outlives its last window, so the menu bar item is installed for the whole run.
@MainActor
extension AppDelegateTests {
    func testAppDoesNotTerminateAfterItsLastWindowCloses() throws {
        let fixture = try AppDelegateTestFixture()
        let appDelegate = fixture.makeAppDelegate()

        XCTAssertFalse(appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    /// `MainWindowPresenter` owns reopen, so SwiftUI must not also open one.
    func testDockReopenIsHandledByThePresenter() throws {
        let fixture = try AppDelegateTestFixture()
        let appDelegate = fixture.makeAppDelegate()

        XCTAssertFalse(
            appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        )
    }

    func testLaunchInstallsTheStatusItemAndTerminationRemovesIt() async throws {
        let fixture = try AppDelegateTestFixture()
        let appDelegate = fixture.makeAppDelegate()

        appDelegate.applicationDidFinishLaunching(appDelegateDidFinishLaunchingNotification())

        XCTAssertEqual(fixture.statusItemFactory.madeItems.count, 1)

        appDelegate.applicationWillTerminate(appDelegateWillTerminateNotification())

        XCTAssertEqual(fixture.statusItemFactory.removedItems.count, 1)
    }

    func testLaunchLeavesTheStatusItemOffWhenTheSettingIsOff() throws {
        let fixture = try AppDelegateTestFixture()
        fixture.settingsService.update { $0.showsMenuBarIcon = false }
        let appDelegate = fixture.makeAppDelegate()

        appDelegate.applicationDidFinishLaunching(appDelegateDidFinishLaunchingNotification())

        XCTAssertTrue(fixture.statusItemFactory.madeItems.isEmpty)
    }
}
