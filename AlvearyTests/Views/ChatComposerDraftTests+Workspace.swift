import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testWorkspaceMenuMovesOutOfComposerOnlyForNewDraftHero() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.thread.isDraft = true
        let chat = makeChatView(fixture: fixture, appState: AppState())
        let isInEmptyState = ChatPresentation.showsWorkspaceInEmptyState(
            isDraft: true, contentMode: .emptyThread, hasSetupPhase: false, isCancellingInitialSetup: false
        )
        XCTAssertTrue(isInEmptyState)
        let draftRow = chat.composerActionRowConfiguration(
            usageSummary: .unreported, showsWorkspaceInEmptyState: isInEmptyState
        )
        XCTAssertNil(draftRow.taskWorkspace)
        XCTAssertFalse(draftRow.showWorktreePicker)
        XCTAssertNotNil(chat.composerTaskWorkspaceConfiguration)

        fixture.thread.isDraft = false
        let materialized = ChatPresentation.showsWorkspaceInEmptyState(
            isDraft: false, contentMode: .emptyThread, hasSetupPhase: false, isCancellingInitialSetup: false
        )
        XCTAssertFalse(materialized)
        XCTAssertNotNil(chat.composerActionRowConfiguration(
            usageSummary: .unreported, showsWorkspaceInEmptyState: materialized
        ).taskWorkspace)
        XCTAssertFalse(ChatPresentation.showsWorkspaceInEmptyState(
            isDraft: true, contentMode: .transcript, hasSetupPhase: false, isCancellingInitialSetup: false
        ))
        XCTAssertFalse(ChatPresentation.showsWorkspaceInEmptyState(
            isDraft: true, contentMode: .emptyThread, hasSetupPhase: true, isCancellingInitialSetup: false
        ))
    }

    func testDraftWorkspaceMenuClosesWhenPlacementChangesAndOnDismantle() {
        let workspace = ChatComposerActionRowView.TaskWorkspaceConfiguration(
            primaryRoot: "/tmp/shared-source", grantedRoots: [], ownershipStrategy: .projectLocal,
            canEdit: true, disabledTooltip: nil, onAddFolders: { _ in }, onRemoveGrant: { _ in }
        )
        let coordinator = ChatWorkspaceControl.Coordinator()
        let button = ComposerWorktreeLocationButton()
        coordinator.button = button
        coordinator.update(ChatWorkspaceControl(contextID: "first-project", configuration: workspace, isEnabled: true))
        coordinator.popover = NSPopover()

        // Shared folders still belong to different placement contexts; an open menu cannot outlive the move.
        coordinator.update(ChatWorkspaceControl(contextID: "second-project", configuration: workspace, isEnabled: true))
        XCTAssertNil(coordinator.popover)

        coordinator.popover = NSPopover()
        button.actionHandler = {}
        ChatWorkspaceControl.dismantleNSView(button, coordinator: coordinator)
        XCTAssertNil(coordinator.popover)
        XCTAssertNil(button.actionHandler)
    }

    func testRetainedDraftWorkspaceMenuCannotMutateReplacementPlacement() throws {
        var changes: [String] = []
        let workspace = ChatComposerActionRowView.TaskWorkspaceConfiguration(
            primaryRoot: "/tmp/shared-source", grantedRoots: ["/tmp/grant"], ownershipStrategy: .projectLocal,
            canEdit: true, disabledTooltip: nil, onAddFolders: { _ in changes.append("add") },
            onRemoveGrant: { _ in changes.append("remove") }, selectedUseWorktree: false,
            onUseWorktreeChange: { _ in changes.append("worktree") }
        )
        let coordinator = ChatWorkspaceControl.Coordinator()
        let original = ChatWorkspaceControl(contextID: "first-project", configuration: workspace, isEnabled: true)
        coordinator.update(original)
        let controller = coordinator.makeMenuController(for: original)
        controller.loadViewIfNeeded()
        let rows = workspaceRows(in: controller.view)
        let remove = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Remove Access to /tmp/grant" })
        let worktree = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Worktree" })

        coordinator.update(ChatWorkspaceControl(contextID: "second-project", configuration: workspace, isEnabled: true))
        XCTAssertTrue(remove.accessibilityPerformPress())
        XCTAssertTrue(worktree.accessibilityPerformPress())
        XCTAssertTrue(changes.isEmpty)

        let replacement = ChatWorkspaceControl(contextID: "second-project", configuration: workspace, isEnabled: true)
        let currentController = coordinator.makeMenuController(for: replacement)
        currentController.loadViewIfNeeded()
        let currentRemove = try XCTUnwrap(workspaceRows(in: currentController.view).first {
            $0.accessibilityLabel() == "Remove Access to /tmp/grant"
        })
        XCTAssertTrue(currentRemove.accessibilityPerformPress())
        XCTAssertEqual(changes, ["remove"])
    }
}

@MainActor
private func workspaceRows(in view: NSView) -> [ComposerReasoningMenuRowView] {
    view.subviews.flatMap { child in
        (child as? ComposerReasoningMenuRowView).map { [$0] } ?? workspaceRows(in: child)
    }
}
