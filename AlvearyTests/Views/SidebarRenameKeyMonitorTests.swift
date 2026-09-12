import AppKit
import XCTest

@testable import Alveary

@MainActor
final class SidebarRenameKeyMonitorTests: XCTestCase {
    func testReturnAndKeypadEnterAllowCapsLockAndKeypadFlags() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }

        try host.sendKey()
        try host.sendKey(keyCode: 76, flags: .numericPad)
        try host.sendKey(flags: .capsLock)
        try host.sendKey(keyCode: 76, flags: [.capsLock, .numericPad])

        XCTAssertEqual(renameCount, 4)
    }

    func testModifiedRepeatedAndUnrelatedKeysPassThrough() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }

        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            try host.sendKey(flags: flags)
            try host.sendKey(keyCode: 76, flags: [flags, .numericPad])
        }
        try host.sendKey(isRepeat: true)
        try host.sendKey(keyCode: 76, isRepeat: true)
        try host.sendKey(keyCode: 125)

        XCTAssertEqual(renameCount, 0)
    }

    func testTextAndControlsRetainReturnEvenWhenTheyFillTheSidebar() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }
        let editor = NSTextView(frame: host.sidebarFrame)
        let button = SidebarRenameMonitorButton(frame: host.sidebarFrame)
        host.root.addSubview(editor)
        host.root.addSubview(button)

        XCTAssertTrue(host.window.makeFirstResponder(editor))
        try host.sendKey()
        XCTAssertTrue(host.window.makeFirstResponder(button))
        try host.sendKey()

        XCTAssertEqual(renameCount, 0)
    }

    func testAnotherPaneAndRowSizedFocusProxyRetainReturn() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }

        host.focusProxy.frame.origin.x = host.sidebarFrame.width
        try host.sendKey()
        host.focusProxy.frame = NSRect(x: 0, y: 0, width: 80, height: 24)
        try host.sendKey()

        XCTAssertEqual(renameCount, 0)
    }

    func testNativeTableFocusUsesItsEnclosingListViewport() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }
        let table = NSTableView(frame: host.sidebarFrame)
        table.headerView = nil
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Task")))
        let scrollView = NSScrollView(frame: host.sidebarFrame)
        scrollView.documentView = table
        host.root.addSubview(scrollView)
        host.root.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.window.makeFirstResponder(table))
        XCTAssertTrue(host.window.firstResponder === table)
        XCTAssertTrue(table.enclosingScrollView === scrollView)
        XCTAssertEqual(
            scrollView.convert(scrollView.bounds, to: nil),
            host.monitor.convert(host.monitor.bounds, to: nil)
        )

        try host.sendKey()

        XCTAssertEqual(renameCount, 1)
    }

    func testInactiveOtherWindowAndHiddenMonitorDoNotRename() throws {
        let host = SidebarRenameMonitorHost()
        let otherHost = SidebarRenameMonitorHost()
        defer {
            host.close()
            otherHost.close()
        }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }

        host.window.simulatesKeyWindow = false
        try host.sendKey()
        host.window.simulatesKeyWindow = true
        try otherHost.sendKey()
        host.monitor.isHidden = true
        try host.sendKey()
        host.monitor.isHidden = false
        host.monitor.frame = .zero
        try host.sendKey()

        XCTAssertEqual(renameCount, 0)
    }

    func testAttachedSheetBlocksRenameUntilDismissed() throws {
        let host = SidebarRenameMonitorHost()
        let sheet = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        defer {
            host.close()
            sheet.close()
        }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }

        host.window.simulatedAttachedSheet = sheet
        try host.sendKey()
        XCTAssertEqual(renameCount, 0)
        host.window.simulatedAttachedSheet = nil
        XCTAssertTrue(host.window.makeFirstResponder(host.focusProxy))
        try host.sendKey()
        XCTAssertEqual(renameCount, 1)
    }

    func testDeclinedRenameCanRetryWithUpdatedCallback() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var firstCallbackCount = 0
        var replacementCallbackCount = 0
        host.monitor.onRename = {
            firstCallbackCount += 1
            return false
        }
        try host.sendKey()

        host.monitor.onRename = {
            replacementCallbackCount += 1
            return true
        }
        // The first Return was deliberately passed to AppKit; restore the sidebar focus
        // before testing that its next eligible event uses the replacement callback.
        XCTAssertTrue(host.window.makeFirstResponder(host.focusProxy))
        try host.sendKey()

        XCTAssertEqual(firstCallbackCount, 1)
        XCTAssertEqual(replacementCallbackCount, 1)
    }

    func testDetachDismantleAndReattachmentKeepOneMonitor() throws {
        let host = SidebarRenameMonitorHost()
        defer { host.close() }
        var renameCount = 0
        host.monitor.onRename = {
            renameCount += 1
            return true
        }
        XCTAssertNil(host.monitor.hitTest(.zero))

        host.monitor.removeFromSuperview()
        try host.sendKey()
        XCTAssertEqual(renameCount, 0)
        host.root.addSubview(host.monitor)
        try host.sendKey()
        XCTAssertEqual(renameCount, 1)
        host.monitor.dismantle()
        try host.sendKey()
        XCTAssertEqual(renameCount, 1)
        host.monitor.removeFromSuperview()
        host.root.addSubview(host.monitor)
        try host.sendKey()
        XCTAssertEqual(renameCount, 2)
    }
}

@MainActor
private final class SidebarRenameMonitorHost {
    let sidebarFrame = NSRect(x: 0, y: 0, width: 240, height: 400)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
    let window: SidebarRenameMonitorWindow
    let monitor: SidebarRenameKeyMonitorView
    let focusProxy: SidebarRenameMonitorFocusView

    init() {
        window = SidebarRenameMonitorWindow(
            contentRect: NSRect(x: -3_000, y: -3_000, width: 480, height: 400),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        monitor = SidebarRenameKeyMonitorView(frame: sidebarFrame)
        // SwiftUI's actual list proxy is a sibling of the List's native view. The hosted
        // SidebarRenameKeyboardTests exercise that real proxy; these isolate event gating.
        focusProxy = SidebarRenameMonitorFocusView(frame: sidebarFrame)
        root.addSubview(focusProxy)
        root.addSubview(monitor)
        window.contentView = root
        XCTAssertTrue(window.makeFirstResponder(focusProxy))
    }

    func sendKey(
        keyCode: UInt16 = 36,
        flags: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) throws {
        let characters = keyCode == 76 ? "\u{3}" : "\r"
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        ))
        NSApp.sendEvent(event)
    }

    func close() {
        monitor.dismantle()
        window.contentView = nil
        window.close()
    }
}

private final class SidebarRenameMonitorWindow: NSWindow {
    var simulatesKeyWindow = true
    /// Supplies sheet state without entering AppKit's live modal and animation loops.
    var simulatedAttachedSheet: NSWindow?

    override var isKeyWindow: Bool { simulatesKeyWindow }
    override var attachedSheet: NSWindow? { simulatedAttachedSheet }
}

private final class SidebarRenameMonitorFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {}
}

private final class SidebarRenameMonitorButton: NSButton {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {}
}
