import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testPinThreadPinsAndReportsTheNewState() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")

        let result = await fixture.pinThread(threadID: "triage-main")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("pinned"))
        XCTAssertEqual(content["thread_id"], .string("triage-main"))
        XCTAssertEqual(content["name"], .string("Triage"))
        XCTAssertEqual(content["is_pinned"], .bool(true))
        XCTAssertTrue(target.isPinned)
        XCTAssertEqual(target.pinnedSortOrder, 0)
    }

    func testUnpinThreadRemovesThePinAndSaysItChangedNothingElse() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        _ = await fixture.pinThread(threadID: "triage-main")

        let result = await fixture.unpinThread(threadID: "triage-main")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("unpinned"))
        XCTAssertEqual(content["is_pinned"], .bool(false))
        XCTAssertFalse(target.isPinned)
        XCTAssertNil(target.pinnedSortOrder)
        XCTAssertTrue(result.text.contains("only its sidebar placement changed"), result.text)
    }

    /// A retry after a lost result should read as done, not as a failure.
    func testPinningAndUnpinningAreIdempotent() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")

        let alreadyUnpinned = await fixture.unpinThread(threadID: "triage-main")
        XCTAssertFalse(alreadyUnpinned.isError)
        XCTAssertEqual(try object(alreadyUnpinned.structuredContent)["status"], .string("already_unpinned"))

        _ = await fixture.pinThread(threadID: "triage-main")
        let alreadyPinned = await fixture.pinThread(threadID: "triage-main")
        XCTAssertFalse(alreadyPinned.isError)
        XCTAssertEqual(try object(alreadyPinned.structuredContent)["status"], .string("already_pinned"))
        XCTAssertEqual(try object(alreadyPinned.structuredContent)["is_pinned"], .bool(true))
        XCTAssertTrue(target.isPinned)
    }

    /// The pinned project already carries the thread, so reporting success would be a lie.
    func testPinningAThreadUnderAPinnedProjectIsRefusedWithTheReason() async throws {
        let fixture = try ThreadHostToolFixture()
        let pinnedProject = Project(path: "/tmp/pinned", name: "Pinned Project")
        pinnedProject.isPinned = true
        let child = try fixture.insertThread(
            name: "Absorbed",
            conversationID: "absorbed-main",
            mode: .project,
            project: pinnedProject
        )
        pinnedProject.threads = [child]
        fixture.modelContext.insert(pinnedProject)
        try fixture.modelContext.save()

        let result = await fixture.pinThread(threadID: "absorbed-main")

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Pinned Project"), result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("error"))
        XCTAssertFalse(child.isPinned)
    }

    func testUnpinningAScheduledAttachedThreadIsAllowed() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Scheduled target", conversationID: "target-main")
        _ = await fixture.pinThread(threadID: "target-main")
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

        let result = await fixture.unpinThread(threadID: "target-main")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertFalse(target.isPinned)
        // Placement moved; the schedule still posts into the same thread.
        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
    }

    func testPinToolsRejectUnknownArchivedAndDraftThreads() async throws {
        let fixture = try ThreadHostToolFixture()
        let archived = try fixture.insertThread(name: "Archived", conversationID: "archived-main")
        archived.archivedAt = Date(timeIntervalSince1970: 10)
        let draft = try fixture.insertThread(name: "Draft", conversationID: "draft-main")
        draft.isDraft = true
        try fixture.modelContext.save()

        for threadID in ["missing-main", "archived-main", "draft-main"] {
            let result = await fixture.pinThread(threadID: threadID)

            XCTAssertTrue(result.isError, threadID)
            XCTAssertEqual(result.text, ThreadHostToolServiceError.threadNotFound.localizedDescription, threadID)
        }
    }

    func testPinToolsRejectUnknownArguments() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Triage", conversationID: "triage-main")

        let unknownKey = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.pinThreadToolName,
                arguments: ["thread_id": .string("triage-main"), "order": .number(1)]
            )
        )

        XCTAssertTrue(unknownKey.isError)
        XCTAssertTrue(unknownKey.text.contains("unsupported field(s): order"), unknownKey.text)
    }

    /// Pinning is trivially reversible by its opposite tool, so an automated run gets it too.
    func testAnAutomatedScheduledRunMayPinAThread() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        fixture.thread.scheduledTaskRun = fixture.attachNonterminalScheduledRun()
        try fixture.modelContext.save()

        let result = await fixture.pinThread(threadID: "triage-main")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("pinned"))
        XCTAssertTrue(target.isPinned)
    }

    /// Unpinning is reversible by its opposite tool and moves nothing a run depends on, so an
    /// automated run gets it even while that run is posting into the thread.
    func testUnpinningFromAnAutomatedScheduledRunIsAllowedOnItsOwnTarget() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        target.isPinned = true
        target.targetedScheduledTaskRuns = [fixture.attachNonterminalScheduledRun()]
        fixture.thread.scheduledTaskRun = fixture.attachNonterminalScheduledRun()
        try fixture.modelContext.save()

        let result = await fixture.unpinThread(threadID: "triage-main")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertFalse(target.isPinned)
    }
}

extension ThreadHostToolFixture {
    func pinThread(threadID: String) async -> AgentCLIKit.AgentHostToolResult {
        await pinCall(ThreadHostToolCatalog.pinThreadToolName, threadID: threadID)
    }

    func unpinThread(threadID: String) async -> AgentCLIKit.AgentHostToolResult {
        await pinCall(ThreadHostToolCatalog.unpinThreadToolName, threadID: threadID)
    }

    private func pinCall(_ toolName: String, threadID: String) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: toolName,
                arguments: ["thread_id": .string(threadID)]
            )
        )
    }
}
