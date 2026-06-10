@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppKitComposerPanelWithNativeQueuedMessages() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                queuedMessages: [
                    QueuedMessage(
                        text: "Follow with the snapshot cleanup once the diff finishes loading.",
                        stagedContext: "Restoring context from local history."
                    )
                ]
            ),
            size: CGSize(width: 1000, height: 220),
            named: "appkit_composer_panel_native_queued_messages",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithNativeQueuedMessagesLight() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                queuedMessages: [
                    QueuedMessage(
                        text: "Follow with the snapshot cleanup once the diff finishes loading.",
                        stagedContext: "Restoring context from local history."
                    )
                ]
            ),
            size: CGSize(width: 1000, height: 220),
            named: "appkit_composer_panel_native_queued_messages_light",
            colorScheme: .light
        )
    }

    func testAppKitComposerPanelWithNativeQueuedMessagesWithoutContext() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                queuedMessages: [
                    QueuedMessage(text: "Test", stagedContext: nil),
                    QueuedMessage(text: "Hi", stagedContext: nil)
                ]
            ),
            size: CGSize(width: 1000, height: 200),
            named: "appkit_composer_panel_native_queued_messages_without_context",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithNativeQueuedMessagesMultiline() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                queuedMessages: [
                    QueuedMessage(
                        text: "Once the diff viewer finishes loading, sweep the composer snapshot baselines, re-record anything that moved, and "
                            + "double-check that queued rows keep even vertical insets when their text wraps onto a second line.",
                        stagedContext: nil
                    )
                ]
            ),
            size: CGSize(width: 1000, height: 200),
            named: "appkit_composer_panel_native_queued_messages_multiline",
            colorScheme: .dark
        )
    }
}
