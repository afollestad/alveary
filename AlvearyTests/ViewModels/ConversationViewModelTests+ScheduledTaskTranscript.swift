import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testTranscriptRecordRefreshFallsBackOnlyWhenFetchThrows() throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: true)
        let fallback = ConversationEventRecord(
            id: "query-fallback",
            type: "message",
            role: "assistant",
            content: "Still visible",
            conversation: fixture.conversation
        )

        let failedWithFallback = ConversationTranscriptRecordRefresh.resolve(
            fallbackEvents: [fallback],
            currentProcessedCount: 1
        ) {
            throw FixtureError.missingConversation
        }
        let failedWithStaleFallback = ConversationTranscriptRecordRefresh.resolve(
            fallbackEvents: [fallback],
            currentProcessedCount: 2
        ) {
            throw FixtureError.missingConversation
        }
        let failedWithoutFallback = ConversationTranscriptRecordRefresh.resolve(
            fallbackEvents: nil,
            currentProcessedCount: 0
        ) {
            throw FixtureError.missingConversation
        }
        let successfulEmptyFetch = ConversationTranscriptRecordRefresh.resolve(
            fallbackEvents: [fallback],
            currentProcessedCount: 2
        ) { [] }

        XCTAssertEqual(failedWithFallback?.map(\.id), [fallback.id])
        XCTAssertNil(failedWithStaleFallback)
        XCTAssertNil(failedWithoutFallback)
        XCTAssertEqual(successfulEmptyFetch?.map(\.id), [])
    }

    func testAutomatedScheduledTurnRetainsPreexistingOccurrenceNote() async throws {
        let scheduledFixture = try ScheduledConversationViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let priorUserMessage = ConversationEventRecord(
            id: "prior-user-message",
            type: "message",
            role: "user",
            content: "Earlier request",
            timestamp: Date(timeIntervalSince1970: 100),
            conversation: fixture.conversation
        )
        let priorAssistantMessage = ConversationEventRecord(
            id: "prior-assistant-message",
            type: "message",
            role: "assistant",
            content: "Earlier response",
            timestamp: Date(timeIntervalSince1970: 200),
            conversation: fixture.conversation
        )
        let note = ConversationEventRecord(
            id: "scheduled-occurrence-note",
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task \"Scheduled audit\" for Jan 15, 2027 at 9:30 AM",
            conversation: fixture.conversation
        )
        fixture.context.insert(priorUserMessage)
        fixture.context.insert(priorAssistantMessage)
        fixture.context.insert(note)
        try fixture.context.save()

        try await fixture.viewModel.startAutomatedScheduledTurn("Run the scheduled audit.")

        let userMessage = try XCTUnwrap(
            try fixture.userMessages().first { $0.content == "Run the scheduled audit." }
        )
        XCTAssertEqual(
            fixture.viewModel.state.grouper.items,
            [
                .userMessage(id: priorUserMessage.id, text: "Earlier request"),
                .assistantMessage(id: priorAssistantMessage.id, text: "Earlier response"),
                .transcriptNote(id: note.id, kind: .scheduledTask(try XCTUnwrap(note.content))),
                .userMessage(id: userMessage.id, text: "Run the scheduled audit.")
            ]
        )
    }

    func testMultipleScheduledTaskNotesRemainAtTheirChronologicalBoundaries() throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: true)
        let earlierAssistant = ConversationEventRecord(
            id: "earlier-assistant",
            type: "message",
            role: "assistant",
            content: "Earlier response",
            timestamp: Date(timeIntervalSince1970: 100),
            conversation: fixture.conversation
        )
        fixture.context.insert(earlierAssistant)
        try fixture.context.save()
        fixture.viewModel.rebuildChatItemsFromConversationRecords(forceFullRebuild: true)

        let first = try insertScheduledTranscriptRun(
            into: fixture,
            id: "first",
            noteText: "Scheduled task \"Daily review\" for Jan 15, 2027 at 9:30 AM",
            timestamp: 200
        )
        fixture.viewModel.rebuildChatItemsFromConversationRecords(forceFullRebuild: true)

        let second = try insertScheduledTranscriptRun(
            into: fixture,
            id: "second",
            noteText: "Scheduled task \"Daily review\" for Jan 16, 2027 at 9:30 AM",
            timestamp: 500
        )
        fixture.viewModel.rebuildChatItemsFromConversationRecords(forceFullRebuild: true)

        XCTAssertEqual(
            fixture.viewModel.state.grouper.items,
            [
                .assistantMessage(id: earlierAssistant.id, text: "Earlier response"),
                .transcriptNote(id: first.note.id, kind: .scheduledTask(try XCTUnwrap(first.note.content))),
                .userMessage(id: first.prompt.id, text: "Run the first review."),
                .assistantMessage(id: first.response.id, text: "First review complete."),
                .transcriptNote(id: second.note.id, kind: .scheduledTask(try XCTUnwrap(second.note.content))),
                .userMessage(id: second.prompt.id, text: "Run the second review."),
                .assistantMessage(id: second.response.id, text: "Second review complete.")
            ]
        )
    }
}

@MainActor
private extension ConversationViewModelTests {
    func insertScheduledTranscriptRun(
        into fixture: ConversationViewModelTestFixture,
        id: String,
        noteText: String,
        timestamp: TimeInterval
    ) throws -> ScheduledTranscriptRun {
        let capitalizedID = id.prefix(1).uppercased() + String(id.dropFirst())
        let note = ConversationEventRecord(
            id: "scheduled-task-\(id)-run",
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: noteText,
            timestamp: Date(timeIntervalSince1970: timestamp),
            conversation: fixture.conversation
        )
        let prompt = ConversationEventRecord(
            id: "\(id)-scheduled-prompt",
            type: "message",
            role: "user",
            content: "Run the \(id) review.",
            timestamp: Date(timeIntervalSince1970: timestamp + 100),
            conversation: fixture.conversation
        )
        let response = ConversationEventRecord(
            id: "\(id)-scheduled-response",
            type: "message",
            role: "assistant",
            content: "\(capitalizedID) review complete.",
            timestamp: Date(timeIntervalSince1970: timestamp + 200),
            conversation: fixture.conversation
        )
        fixture.context.insert(note)
        fixture.context.insert(prompt)
        fixture.context.insert(response)
        try fixture.context.save()
        return ScheduledTranscriptRun(note: note, prompt: prompt, response: response)
    }
}

private struct ScheduledTranscriptRun {
    let note: ConversationEventRecord
    let prompt: ConversationEventRecord
    let response: ConversationEventRecord
}
