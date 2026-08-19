import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testArchiveThreadAppliesImmediatelyAndTearsDownItsRuntime() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Nightly audit", conversationID: "target-main")
        target.isPinned = true
        target.pinnedSortOrder = 0
        try fixture.modelContext.save()

        let result = await fixture.archive(threadID: "target-main")

        XCTAssertFalse(result.isError)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("archived"))
        XCTAssertEqual(content["thread_id"], .string("target-main"))
        XCTAssertEqual(content["name"], .string("Nightly audit"))
        XCTAssertNotNil(target.archivedAt)
        XCTAssertFalse(target.isPinned)
        let destroyCalls = await fixture.sidebar.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls, ["target-main"])
        // Never described as deletion: nothing here deletes a thread.
        XCTAssertTrue(result.text.contains("restore it from Alveary's Archived screen"), result.text)
        XCTAssertTrue(result.text.contains("not deleted"), result.text)
    }

    /// A retry after a lost result should read as done, not as a failure.
    func testArchivingAnAlreadyArchivedThreadSucceedsAndChangesNothing() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Nightly audit", conversationID: "target-main")
        let archivedAt = Date(timeIntervalSince1970: 10)
        target.archivedAt = archivedAt
        try fixture.modelContext.save()

        let result = await fixture.archive(threadID: "target-main")

        XCTAssertFalse(result.isError)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_archived"))
        XCTAssertEqual(target.archivedAt, archivedAt)
        let destroyCalls = await fixture.sidebar.agentsManager.destroyCalls()
        XCTAssertTrue(destroyCalls.isEmpty)
    }

    /// Archiving kills the calling provider process mid-call, so the result would never arrive.
    func testAConversationCannotArchiveItsOwnThread() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.archive(threadID: fixture.conversation.id)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            ThreadHostToolServiceError.cannotArchiveOwnThread.localizedDescription
        )
        XCTAssertNil(fixture.thread.archivedAt)
    }

    func testArchiveThreadRejectsUnknownAndDraftThreads() async throws {
        let fixture = try ThreadHostToolFixture()
        let draft = try fixture.insertThread(name: "Draft", conversationID: "draft-main")
        draft.isDraft = true
        try fixture.modelContext.save()

        for threadID in ["missing-main", "draft-main"] {
            let result = await fixture.archive(threadID: threadID)

            XCTAssertTrue(result.isError, threadID)
            XCTAssertEqual(result.text, ThreadHostToolServiceError.threadNotFound.localizedDescription, threadID)
        }
        XCTAssertNil(draft.archivedAt)
    }

    func testArchiveThreadConvertsAnAttachedScheduleToReuse() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Scheduled target", conversationID: "target-main")
        let definition = ScheduledTask(
            title: "Nightly sweep",
            prompt: "Sweep the release branch.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "Etc/UTC",
            providerID: "codex",
            targetThread: target
        )
        target.targetedScheduledTasks = [definition]
        fixture.modelContext.insert(definition)
        try fixture.modelContext.save()

        let result = await fixture.archive(threadID: "target-main")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertNotNil(target.archivedAt)
        XCTAssertEqual(definition.decodedDestination, .reusedThread)
        XCTAssertNil(definition.targetThread)
    }

    /// The archive already committed, so reporting an error would tell the model to retry
    /// something that already happened.
    func testRuntimeCleanupFailureStillReportsTheArchiveAsApplied() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Nightly audit", conversationID: "target-main")
        await fixture.sidebar.agentsManager.setDestroyError(.destroyFailed("target-main"), for: "target-main")

        let result = await fixture.archive(threadID: "target-main")

        XCTAssertFalse(result.isError)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("archived"))
        XCTAssertTrue(result.text.contains("Runtime cleanup reported"), result.text)
        XCTAssertNotNil(target.archivedAt)
    }

    func testProviderSessionDiagnosticsAnnotateTheMessageWithoutFailingTheTool() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .archive, message: "Codex archive failed")
        let fixture = try ThreadHostToolFixture(
            providerSessionActions: RecordingProviderSessionActionService(archiveDiagnostics: [diagnostic])
        )
        let target = try fixture.insertThread(name: "Nightly audit", conversationID: "target-main")

        let result = await fixture.archive(threadID: "target-main")

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains(diagnostic.toastMessage), result.text)
        XCTAssertNotNil(target.archivedAt)
    }

    func testArchiveThreadRejectsUnknownArgumentsAndMissingIdentifiers() async throws {
        let fixture = try ThreadHostToolFixture()

        let unknownKey = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.archiveThreadToolName,
                arguments: ["thread_id": .string("target-main"), "force": .bool(true)]
            )
        )
        XCTAssertTrue(unknownKey.isError)
        XCTAssertTrue(unknownKey.text.contains("unsupported field(s): force"), unknownKey.text)

        let missing = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.archiveThreadToolName)
        )
        XCTAssertTrue(missing.isError)
        XCTAssertTrue(missing.text.contains("arguments.thread_id"), missing.text)
    }
}

extension ThreadHostToolFixture {
    func archive(threadID: String) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.archiveThreadToolName,
                arguments: ["thread_id": .string(threadID)]
            )
        )
    }
}
