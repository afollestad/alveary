import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAutomatedScheduledTurnRetainsPreexistingOccurrenceNote() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let note = ConversationEventRecord(
            id: "scheduled-occurrence-note",
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task for Jan 15, 2027 at 9:30 AM",
            conversation: fixture.conversation
        )
        fixture.context.insert(note)
        try fixture.context.save()

        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")

        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(
            fixture.viewModel.state.grouper.items,
            [
                .transcriptNote(id: note.id, kind: .scheduledTask(try XCTUnwrap(note.content))),
                .userMessage(id: userMessage.id, text: "Run the scheduled audit.")
            ]
        )
    }
}
