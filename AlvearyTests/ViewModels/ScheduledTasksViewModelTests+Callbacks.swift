import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testExactTabTargetSurvivesEditorRoundTripAndMissingTargetIsNotReset() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = AgentThread(name: "Caller", mode: .task)
        let main = Conversation(harness: "claude", thread: thread)
        let secondary = Conversation(harness: "codex", isMain: false, displayOrder: 1, thread: thread)
        thread.conversations = [main, secondary]
        fixture.context.insert(thread)
        try fixture.insertDefinition(id: "callback", state: .active)
        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        definition.destination = .existingThread
        definition.targetThread = thread
        try fixture.context.save()
        fixture.viewModel.reload()
        XCTAssertEqual(Set(fixture.viewModel.existingThreadTargets.map(\.conversationID)), Set([main.id, secondary.id]))
        var draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        draft.selectTargetConversation(main.id)
        XCTAssertNil(draft.exactTargetConversationID)
        draft.selectTargetConversation(secondary.id)
        XCTAssertEqual(draft.targetConversationID, secondary.id)
        draft.prompt = "Updated callback"
        XCTAssertTrue(fixture.viewModel.save(draft))
        XCTAssertEqual(definition.exactTargetConversationID, secondary.id)
        XCTAssertEqual(fixture.viewModel.makeRowPresentation(definition).harnessID, "codex")
        let originalID = secondary.id
        fixture.context.delete(secondary)
        try fixture.context.save()
        let missingDraft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        XCTAssertEqual(missingDraft.targetConversationID, originalID)
        XCTAssertFalse(fixture.viewModel.save(missingDraft))
        XCTAssertEqual(definition.exactTargetConversationID, originalID)
    }
}
