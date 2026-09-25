import AppKit
import XCTest

@testable import Alveary

@MainActor
final class MainWindowPresenterTests: XCTestCase {
    func testBridgeRegistersItsWindowWithoutMatchingATitle() {
        let presenter = MainWindowPresenter()
        let unrelatedWindow = makeWindow(title: "Alveary")
        defer { unrelatedWindow.close() }

        XCTAssertNil(presenter.mainWindow)

        let mainWindow = makeWindow(title: "A different title")
        defer { mainWindow.close() }
        mainWindow.contentView = MainWindowRegistrationAnchorView(presenter: presenter)

        XCTAssertTrue(presenter.mainWindow === mainWindow)
        unrelatedWindow.close()
        XCTAssertTrue(presenter.mainWindow === mainWindow)
    }

    func testClosingARetainedWindowClearsItsRegistration() {
        let presenter = MainWindowPresenter()
        let window = makeWindow()
        window.contentView = MainWindowRegistrationAnchorView(presenter: presenter)

        window.close()

        XCTAssertTrue(NSApp.windows.contains { $0 === window })
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertNil(presenter.mainWindow)
    }

    func testRetainedWindowCanRegisterAgainWithoutReattachingItsView() {
        let presenter = MainWindowPresenter()
        let window = makeWindow()
        defer { window.close() }
        let anchor = MainWindowRegistrationAnchorView(presenter: presenter)
        window.contentView = anchor
        window.close()

        for _ in 0..<2 {
            XCTAssertNil(presenter.mainWindow)
            XCTAssertTrue(anchor.window === window)

            // Emulate the whole reopen/close notification cycle without showing the test window;
            // calling close() again on the already closed native window would post nothing.
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            XCTAssertTrue(presenter.mainWindow === window)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            XCTAssertNil(presenter.mainWindow)
        }
    }

    func testOlderWindowClosingAndDetachingCannotClearItsReplacement() {
        let presenter = MainWindowPresenter()
        let oldWindow = makeWindow()
        oldWindow.contentView = MainWindowRegistrationAnchorView(presenter: presenter)
        let replacementWindow = makeWindow()
        defer { replacementWindow.close() }
        replacementWindow.contentView = MainWindowRegistrationAnchorView(presenter: presenter)

        oldWindow.close()
        XCTAssertTrue(presenter.mainWindow === replacementWindow)

        oldWindow.contentView = nil
        XCTAssertTrue(presenter.mainWindow === replacementWindow)
    }

    func testDetachingTheBridgeClearsRegistrationAndStopsObserving() {
        let presenter = MainWindowPresenter()
        let window = makeWindow()
        defer { window.close() }
        let anchor = MainWindowRegistrationAnchorView(presenter: presenter)
        window.contentView = anchor

        anchor.removeFromSuperview()
        XCTAssertNil(presenter.mainWindow)

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertNil(presenter.mainWindow)
    }

    func testHiddenRegisteredWindowDoesNotTriggerBackgroundReopening() {
        let presenter = MainWindowPresenter()
        let window = makeWindow()
        defer { window.close() }
        window.contentView = MainWindowRegistrationAnchorView(presenter: presenter)
        var openCount = 0
        presenter.register { openCount += 1 }

        XCTAssertFalse(window.isVisible)
        presenter.activateIfWindowClosed()

        XCTAssertTrue(presenter.mainWindow === window)
        XCTAssertEqual(openCount, 0)
    }

    func testActivateReportsWhenItHasNothingToShow() {
        let presenter = MainWindowPresenter()

        XCTAssertFalse(presenter.activate())
    }

    func testActivateOpensTheSceneWhenOnlyAnOpenerIsRegistered() {
        let presenter = MainWindowPresenter()
        var openCount = 0
        presenter.register { openCount += 1 }

        XCTAssertTrue(presenter.activate())
        XCTAssertEqual(openCount, 1)
    }

    private func makeWindow(title: String = "Alveary") -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }
}
