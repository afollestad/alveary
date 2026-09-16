import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testScheduledCallbackWidgetAppliedWithoutOutcomeMarker() throws {
        let content = try XCTUnwrap(ScheduledTaskWidgetParsing.proposalContent(
            input: #"{"action":"create","title":"Say hello","prompt":"Say hello.","schedule":{"kind":"once","after_seconds":1800}}"#,
            output: #"{"status":"applied","task_id":"callback","scheduled_at":"2030-01-01T15:00:00.000Z","destination":"current_thread"}"#,
            isError: false
        ))
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptHostToolWidgetRowView()
                view.configure(.init(entry: HostToolWidgetEntry(
                    id: "callback", toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName),
                    content: .scheduledTaskProposal(content), isComplete: true
                ), bubbleMaxWidth: 640))
                return view
            },
            size: CGSize(width: 700, height: 200), named: "scheduled_callback_applied"
        )
    }

    func testScheduledCallbackEditorSelectedSecondaryTab() throws {
        try assertCallbackEditor(unavailable: false, named: "scheduled_callback_secondary_tab")
    }

    func testScheduledCallbackEditorUnavailableTab() throws {
        try assertCallbackEditor(unavailable: true, named: "scheduled_callback_unavailable_tab")
    }

    private func assertCallbackEditor(unavailable: Bool, named name: String) throws {
        let fixture = try ScheduledTasksSnapshotFixture(includeTasks: false)
        var draft = fixture.viewModel.makeNewDraft()
        draft.destination = .existingThread
        draft.targetConversationID = "secondary"
        draft.exactTargetConversationID = "secondary"
        var options = [ScheduledTaskThreadOption(conversationID: "main", label: "Release review · Main")]
        if !unavailable {
            options.append(ScheduledTaskThreadOption(conversationID: "secondary", label: "Release review · Follow-up"))
        }
        assertMacSnapshot(
            ScheduledTaskEditorWorkspaceSection(
                projects: fixture.viewModel.projects, threads: options, sections: [],
                draft: .constant(draft), onOpenReusedThread: { _ in }
            ).padding(24),
            size: CGSize(width: 760, height: 220), named: name
        )
    }
}
