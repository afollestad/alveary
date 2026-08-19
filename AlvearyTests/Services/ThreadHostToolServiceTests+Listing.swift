import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testListProjectsReturnsRegisteredProjectsSortedByPath() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.modelContext.insert(Project(path: "/tmp/zulu", name: "Zulu"))
        fixture.modelContext.insert(Project(path: "/tmp/alpha", name: "Alpha"))
        try fixture.modelContext.save()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listProjectsToolName)
        )

        XCTAssertFalse(result.isError)
        // The rows ride in the text too — a plain-text-fallback provider sees nothing else.
        XCTAssertEqual(
            result.text,
            "Found 3 Projects:\n" +
                "- Alpha (/tmp/alpha)\n" +
                "- Source Project (/tmp/source-project)\n" +
                "- Zulu (/tmp/zulu)"
        )
        let projects = try array(try object(result.structuredContent)["projects"])
        XCTAssertEqual(
            try projects.map { try object($0)["path"] },
            [.string("/tmp/alpha"), .string("/tmp/source-project"), .string("/tmp/zulu")]
        )
    }

    func testListThreadsReturnsSettingsMostRecentFirst() async throws {
        let fixture = try ThreadHostToolFixture()
        let older = try fixture.insertThread(name: "Release chat", conversationID: "release-main")
        older.modifiedAt = Date(timeIntervalSince1970: 100)
        older.effort = "low"
        older.permissionMode = "never"
        let newer = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        newer.isPinned = true
        newer.model = "gpt-5"
        newer.modifiedAt = Date(timeIntervalSince1970: 200)
        try fixture.modelContext.save()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listThreadsToolName)
        )

        XCTAssertFalse(result.isError)
        let threads = try array(try object(result.structuredContent)["threads"])
        // The source thread has no `modifiedAt` and sorts last.
        XCTAssertEqual(
            try threads.map { try object($0)["id"] },
            [.string("triage-main"), .string("release-main"), .string(fixture.conversation.id)]
        )
        let first = try object(try XCTUnwrap(threads.first))
        XCTAssertEqual(first["name"], .string("Triage"))
        XCTAssertEqual(first["workspace"], .string("task"))
        XCTAssertEqual(first["workspace_kind"], .string("task"))
        XCTAssertEqual(first["model"], .string("gpt-5"))
        XCTAssertEqual(first["is_pinned"], .bool(true))
        XCTAssertEqual(first["modified_at"], .string("1970-01-01T00:03:20.000Z"))
        XCTAssertNil(first["project_path"])

        let second = try object(threads[1])
        XCTAssertEqual(second["effort"], .string("low"))
        XCTAssertEqual(second["permission_mode"], .string("never"))
        // No stored model reads as the provider's default rather than as a missing field.
        XCTAssertEqual(second["model"], .string("default"))
        XCTAssertEqual(second["provider"], .string("codex"))

        let source = try object(threads[2])
        XCTAssertEqual(source["workspace"], .string("project: Source Project"))
        XCTAssertEqual(source["workspace_kind"], .string("project"))
        XCTAssertEqual(source["project_path"], .string("/tmp/source-project"))
        XCTAssertNil(source["modified_at"])

        XCTAssertTrue(
            result.text.contains(
                "- \"Triage\" (id: triage-main, task, codex, model gpt-5, effort medium, permissions default, " +
                    "pinned, section Tasks)"
            ),
            result.text
        )
    }

    /// Answers "which thread am I in" without a second tool.
    func testListThreadsMarksTheCallingConversationsThread() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Elsewhere", conversationID: "elsewhere-main")

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listThreadsToolName)
        )

        let threads = try array(try object(result.structuredContent)["threads"])
        let currentRows = try threads.filter { try object($0)["is_current"] == .bool(true) }
        XCTAssertEqual(try currentRows.map { try object($0)["id"] }, [.string(fixture.conversation.id)])
        XCTAssertTrue(result.text.contains("this conversation's thread"), result.text)
    }

    func testListThreadsOmitsUnlistableThreadsEntirely() async throws {
        let fixture = try ThreadHostToolFixture()
        let archived = try fixture.insertThread(name: "Archived", conversationID: "archived-main")
        archived.archivedAt = Date(timeIntervalSince1970: 10)
        let forkPending = try fixture.insertThread(name: "Fork", conversationID: "fork-main")
        forkPending.isForkBootstrapPending = true
        let draft = try fixture.insertThread(name: "Draft", conversationID: "draft-main")
        draft.isDraft = true
        let forked = try fixture.insertThread(name: "Forked", conversationID: "forked-main")
        forked.conversations.append(Conversation(id: "forked-second-main", provider: "codex", thread: forked))
        try fixture.modelContext.save()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listThreadsToolName)
        )

        let threads = try array(try object(result.structuredContent)["threads"])
        XCTAssertEqual(try threads.map { try object($0)["id"] }, [.string(fixture.conversation.id)])
        // Nothing about an omitted thread reaches the provider, not even its name.
        let encodedResult = try encoded(result)
        for name in ["Archived", "Fork", "Draft", "Forked"] {
            XCTAssertFalse(encodedResult.contains(name), name)
        }
    }

    /// Broader than scheduling's target eligibility: a pinned project's child is listed, because
    /// listing promises no pin.
    func testListThreadsIncludesChildrenOfPinnedProjects() async throws {
        let fixture = try ThreadHostToolFixture()
        let pinnedProject = Project(path: "/tmp/pinned", name: "Pinned")
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

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listThreadsToolName)
        )

        let threads = try array(try object(result.structuredContent)["threads"])
        XCTAssertTrue(try threads.contains { try object($0)["id"] == .string("absorbed-main") })
        // Listing and scheduling agree on a pinned project's child: it renders inside that
        // project, so nothing about the absorbed pin makes it unreachable.
        XCTAssertTrue(child.isEligibleScheduledTaskTarget)
    }

    func testReadToolsRejectArgumentsAndNameThemselves() async throws {
        let fixture = try ThreadHostToolFixture()

        for toolName in [
            ThreadHostToolCatalog.listThreadsToolName,
            ThreadHostToolCatalog.listProjectsToolName
        ] {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(
                    name: toolName,
                    arguments: ["filter": .string("anything")]
                )
            )

            XCTAssertTrue(result.isError, toolName)
            XCTAssertTrue(result.text.contains("\(toolName) does not accept arguments."), result.text)
        }
    }
}
