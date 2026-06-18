import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationRestoreContextTests: XCTestCase {
    func testRefreshPendingRestoreContextIncludesRecentTranscriptToolActivityAndErrorNote() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(
            type: "message",
            role: "user",
            content: "Please continue the auth rollback investigation"
        )
        fixture.addEvent(
            type: "message",
            role: "assistant",
            content: "I narrowed it down to the session recreation path."
        )
        fixture.addEvent(type: "tool_call", toolId: "tool-1", toolName: "Read")
        fixture.addEvent(
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "Opened the runtime lifecycle code",
            isError: false
        )
        fixture.addEvent(type: "tool_call", toolId: "tool-2", toolName: "Edit")
        fixture.addEvent(
            type: "tool_result",
            toolId: "tool-2",
            toolOutputStderr: "Permission denied while updating the session file",
            isError: true
        )
        fixture.addEvent(type: "tokens", isError: true, stopReason: "Agent turn failed after the permission denial")

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("Restoring context from local history."))
        XCTAssertTrue(pendingRestoreContext.contains("This is a fresh provider session; do not assume memory from earlier turns."))
        XCTAssertTrue(pendingRestoreContext.contains("User: Please continue the auth rollback investigation"))
        XCTAssertTrue(pendingRestoreContext.contains("Assistant: I narrowed it down to the session recreation path."))
        XCTAssertTrue(pendingRestoreContext.contains("Read: succeeded. Opened the runtime lifecycle code"))
        XCTAssertTrue(pendingRestoreContext.contains("Edit: failed. Permission denied while updating the session file"))
        XCTAssertTrue(pendingRestoreContext.contains("Last session note:"))
        XCTAssertTrue(pendingRestoreContext.contains("Agent turn failed after the permission denial"))
    }

    func testRefreshPendingRestoreContextUsesFallbackForGenericTokenErrorNote() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "user", content: "Resume after the failed model turn")
        fixture.addEvent(type: "tokens", isError: true, stopReason: "stop_sequence")

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("Last session note:"))
        XCTAssertTrue(pendingRestoreContext.contains("The previous run ended with an error."))
        XCTAssertFalse(pendingRestoreContext.contains("stop_sequence"))
    }

    func testRefreshPendingRestoreContextUsesLatestNotificationWhenNoErrorNoteExists() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "user", content: "Pick up from the last restore")
        fixture.addEvent(type: "notification", content: "Worktree setup completed", notificationType: "setup")

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("setup: Worktree setup completed"))
    }

    func testRefreshPendingRestoreContextUsesStopMessageAsSessionNote() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "user", content: "Resume the interrupted setup")
        fixture.addEvent(type: "stop", content: "User cancelled after checking the worktree")

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("User cancelled after checking the worktree"))
    }

    func testRefreshPendingRestoreContextUsesErrorMessageAsSessionNote() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "assistant", content: "Runtime was nearly ready")
        fixture.addEvent(type: "error", content: "Structured stream decoding failed")

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("Structured stream decoding failed"))
    }

    func testRefreshPendingRestoreContextExcludesNormalContextCompaction() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "user", content: "Continue after compaction")
        fixture.addEvent(type: ConversationContextCompaction.startedType, content: "auto", toolId: "compact-1")
        fixture.addEvent(type: ConversationContextCompaction.completedType, content: "Reduced context", toolId: "compact-1")

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("Continue after compaction"))
        XCTAssertFalse(pendingRestoreContext.contains("Automatically compact"))
        XCTAssertFalse(pendingRestoreContext.contains("Reduced context"))
    }

    func testRefreshPendingRestoreContextExcludesSteeredConversationMarker() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "user", content: "Continue after steering")
        fixture.addEvent(
            type: ConversationEventRecord.steeredConversationType,
            content: ConversationSteering.displayMessage
        )

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("Continue after steering"))
        XCTAssertFalse(pendingRestoreContext.contains(ConversationSteering.displayMessage))
    }

    func testRefreshPendingRestoreContextIncludesFailedContextCompactionError() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        fixture.addEvent(type: "message", role: "assistant", content: "Working before compaction")
        fixture.addEvent(
            type: ConversationContextCompaction.failedType,
            content: "Compact hook failed",
            toolId: "compact-1",
            isError: true
        )

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertTrue(pendingRestoreContext.contains("Last session note:"))
        XCTAssertTrue(pendingRestoreContext.contains("Context compaction failed: Compact hook failed"))
    }

    func testRefreshPendingRestoreContextKeepsOnlyRecentTranscriptEntries() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        for index in 1...8 {
            fixture.addEvent(type: "message", role: "user", content: "Question \(index)")
        }

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertFalse(pendingRestoreContext.contains("Question 1"))
        XCTAssertFalse(pendingRestoreContext.contains("Question 2"))
        XCTAssertTrue(pendingRestoreContext.contains("Question 3"))
        XCTAssertTrue(pendingRestoreContext.contains("Question 8"))
    }

    func testRefreshPendingRestoreContextKeepsOnlyRecentToolEntries() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation

        for index in 1...4 {
            fixture.addEvent(type: "tool_call", toolId: "tool-\(index)", toolName: "Read \(index)")
            fixture.addEvent(
                type: "tool_result",
                toolId: "tool-\(index)",
                toolOutput: "Output \(index)",
                isError: false
            )
        }

        conversation.refreshPendingRestoreContextFromHistory()

        let pendingRestoreContext = try XCTUnwrap(conversation.pendingRestoreContext)
        XCTAssertFalse(pendingRestoreContext.contains("Read 1: succeeded. Output 1"))
        XCTAssertTrue(pendingRestoreContext.contains("Read 2: succeeded. Output 2"))
        XCTAssertTrue(pendingRestoreContext.contains("Read 4: succeeded. Output 4"))
    }

    func testRefreshPendingRestoreContextClearsExistingValueWhenNoSavedHistoryExists() throws {
        let fixture = try ConversationRestoreContextFixture()
        let conversation = fixture.conversation
        conversation.pendingRestoreContext = "Old restore summary"

        conversation.refreshPendingRestoreContextFromHistory()

        XCTAssertNil(conversation.pendingRestoreContext)
    }
}

@MainActor
private struct ConversationRestoreContextFixture {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread
    let conversation: Conversation

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        context = ModelContext(container)

        project = Project(path: "/tmp/restore-context-project", name: "Restore Context")
        thread = AgentThread(name: "Restore Thread", project: project)
        conversation = Conversation(title: "Main", provider: "claude", thread: thread)
        project.threads = [thread]
        thread.conversations = [conversation]

        context.insert(project)
        try context.save()
    }

    func addEvent(
        type: String,
        role: String? = nil,
        content: String? = nil,
        toolId: String? = nil,
        toolName: String? = nil,
        toolOutput: String? = nil,
        toolOutputStderr: String? = nil,
        isError: Bool = false,
        stopReason: String? = nil,
        notificationType: String? = nil
    ) {
        let timestamp = Date(timeIntervalSince1970: TimeInterval(conversation.events.count))
        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: type,
            role: role,
            content: content,
            toolId: toolId,
            toolName: toolName,
            toolOutput: toolOutput,
            toolOutputStderr: toolOutputStderr,
            isError: isError,
            notificationType: notificationType,
            stopReason: stopReason,
            timestamp: timestamp,
            conversation: conversation
        )
        conversation.events.append(record)
    }
}
