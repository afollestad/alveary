@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatComposerVoiceInputEventTests {
    func testMountNotifiesVoiceAvailabilityWithFallbackSelection() async throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let editorHandle = AppKitChatComposerEditorHandle()
        var notificationCount = 0
        panel.configure(panelConfiguration(
            voiceEditorHandle: editorHandle,
            onVoiceInputAvailabilityChange: { notificationCount += 1 }
        ))
        let countBeforeMount = notificationCount
        XCTAssertNil(panel.editorController.latestSelection)
        XCTAssertFalse(editorHandle.canStartVoiceInput)

        let window = NSWindow(
            contentRect: NSRect(x: -1400, y: -1100, width: 420, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = panel
        await Task.yield()

        XCTAssertNil(panel.editorController.latestSelection)
        XCTAssertGreaterThan(notificationCount, countBeforeMount)
        XCTAssertTrue(editorHandle.canStartVoiceInput)
    }
}
