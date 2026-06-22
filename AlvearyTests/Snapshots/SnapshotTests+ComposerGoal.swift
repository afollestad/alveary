import AgentCLIKit
@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppKitComposerPanelWithActiveGoalStatus() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                topContentConfiguration: goalTopContentConfiguration(items: [
                    activeGoalItem()
                ])
            ),
            size: CGSize(width: 1000, height: 190),
            named: "appkit_composer_panel_active_goal_status",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithActiveGoalAndQueuedMessages() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                topContentConfiguration: goalTopContentConfiguration(items: [
                    activeGoalItem()
                ]),
                queuedMessages: [
                    QueuedMessage(
                        text: "After the goal is accepted, keep this as an ordinary queued follow-up.",
                        stagedContext: nil
                    )
                ]
            ),
            size: CGSize(width: 1000, height: 260),
            named: "appkit_composer_panel_active_goal_with_queued_messages",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithActiveGoalAndStagedContext() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                topContentConfiguration: goalTopContentConfiguration(items: [
                    activeGoalItem(),
                    .stagedContext(.init(
                        context: "Restoring focused implementation notes from the previous session.",
                        onDismiss: {}
                    ))
                ])
            ),
            size: CGSize(width: 1000, height: 230),
            named: "appkit_composer_panel_active_goal_with_staged_context",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithActiveGoalAndBanners() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                topContentConfiguration: goalTopContentConfiguration(items: [
                    .inlineBanner(.init(
                        message: "Session handoff failed: the hidden handoff prompt returned no context.",
                        severity: .error,
                        actionTitle: "Retry",
                        onAction: {},
                        onDismiss: {}
                    )),
                    .inlineBanner(.init(
                        message: "Continuing from the last provider session.",
                        severity: .info,
                        actionTitle: nil,
                        onAction: nil,
                        onDismiss: nil
                    )),
                    activeGoalItem()
                ])
            ),
            size: CGSize(width: 1000, height: 270),
            named: "appkit_composer_panel_active_goal_with_banners",
            colorScheme: .dark
        )
    }

    func testAppKitComposerPanelWithTerminalGoalStatus() {
        assertMacSnapshot(
            AppKitComposerPanelNativeRowSnapshot(
                topContentConfiguration: goalTopContentConfiguration(items: [
                    terminalGoalItem()
                ])
            ),
            size: CGSize(width: 1000, height: 190),
            named: "appkit_composer_panel_terminal_goal_status",
            colorScheme: .dark
        )
    }

    private func goalTopContentConfiguration(
        items: [AppKitChatComposerTopContentView.Item]
    ) -> AppKitChatComposerTopContentView.Configuration {
        .init(items: items)
    }

    private func activeGoalItem() -> AppKitChatComposerTopContentView.Item {
        .goalStatus(.init(
            snapshot: AgentGoalSnapshot(
                objective: "Finish Goal mode across Codex and Claude without duplicating the first provider turn.",
                status: .active,
                availableActions: [.pause, .delete],
                elapsedSeconds: 75,
                turnCount: 2,
                tokenCount: 12_480
            ),
            actionError: nil,
            onPause: {},
            onResume: nil,
            onDelete: {},
            onDismissTerminal: nil
        ))
    }

    private func terminalGoalItem() -> AppKitChatComposerTopContentView.Item {
        .goalStatus(.init(
            snapshot: AgentGoalSnapshot(
                objective: "Finish Goal mode across Codex and Claude without duplicating the first provider turn.",
                status: .achieved,
                elapsedSeconds: 420,
                turnCount: 8,
                tokenCount: 34_100
            ),
            actionError: nil,
            onPause: nil,
            onResume: nil,
            onDelete: nil,
            onDismissTerminal: {}
        ))
    }
}
