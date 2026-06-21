import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSessionHandoffShowsInProgressNoteThenCompletesSameNote() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        var records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let startedNote = try XCTUnwrap(records.first { ConversationSessionHandoff.isDisplayMessage($0.content) })
        XCTAssertEqual(startedNote.content, ConversationSessionHandoff.startedDisplayMessage)
        XCTAssertTrue(
            fixture.viewModel.state.grouper.items.contains(
                .transcriptNote(id: startedNote.id, kind: .sessionHandoffInProgress)
            )
        )

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Carry this context forward.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))
        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let handoffNotes = records.filter { ConversationSessionHandoff.isDisplayMessage($0.content) }
        XCTAssertEqual(handoffNotes.map(\.id), [startedNote.id])
        XCTAssertEqual(handoffNotes.first?.content, ConversationSessionHandoff.completedDisplayMessage)
        XCTAssertTrue(
            fixture.viewModel.state.grouper.items.contains(
                .transcriptNote(id: startedNote.id, kind: .sessionHandoff)
            )
        )
        XCTAssertFalse(
            fixture.viewModel.state.grouper.items.contains(
                .transcriptNote(id: startedNote.id, kind: .sessionHandoffInProgress)
            )
        )
    }
}
