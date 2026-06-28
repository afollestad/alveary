@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testPausedQueueSendConfirmationWindowModal() {
        assertMacSnapshot(
            PausedQueueSendConfirmationModal(
                messageText: "You are about to send a message. Do you want to clear the 2 messages previously queued?",
                isResolving: false,
                onDismiss: {},
                onClearQueue: {},
                onSendMessage: {}
            ),
            size: CGSize(width: 900, height: 640),
            named: "paused_queue_send_confirmation_window_modal",
            colorScheme: .dark
        )
    }

    func testPausedQueueSendConfirmationWindowModalLightMode() {
        assertMacSnapshot(
            PausedQueueSendConfirmationModal(
                messageText: "You are about to send a message. Do you want to clear the 2 messages previously queued?",
                isResolving: false,
                onDismiss: {},
                onClearQueue: {},
                onSendMessage: {}
            ),
            size: CGSize(width: 900, height: 640),
            named: "paused_queue_send_confirmation_window_modal_light",
            colorScheme: .light
        )
    }
}
