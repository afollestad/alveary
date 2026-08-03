import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testListProjectsReturnsRegisteredProjectsSortedByPath() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        fixture.modelContext.insert(Project(path: "/tmp/zulu", name: "Zulu"))
        fixture.modelContext.insert(Project(path: "/tmp/alpha", name: "Alpha"))
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listProjectsToolName)
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
        XCTAssertEqual(try object(try XCTUnwrap(projects.first))["name"], .string("Alpha"))
    }

    func testListThreadsReturnsEligibleTargetsWithPinState() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let unpinned = try fixture.insertTargetThread(name: "Release chat", conversationID: "release-main")
        unpinned.modifiedAt = Date(timeIntervalSince1970: 100)
        let pinned = try fixture.insertTargetThread(name: "Triage", conversationID: "triage-main")
        pinned.isPinned = true
        pinned.modifiedAt = Date(timeIntervalSince1970: 200)
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listThreadsToolName)
        )

        XCTAssertFalse(result.isError)
        let threads = try array(try object(result.structuredContent)["threads"])
        // Most recently touched first; the source thread has no `modifiedAt` and sorts last.
        XCTAssertEqual(
            try threads.map { try object($0)["id"] },
            [.string("triage-main"), .string("release-main"), .string(fixture.conversation.id)]
        )
        let first = try object(try XCTUnwrap(threads.first))
        XCTAssertEqual(first["name"], .string("Triage"))
        XCTAssertEqual(first["workspace"], .string("task"))
        XCTAssertEqual(first["is_pinned"], .bool(true))
        XCTAssertEqual(try object(threads[1])["is_pinned"], .bool(false))
        XCTAssertEqual(try object(threads[2])["workspace"], .string("project: Source Project"))
        XCTAssertTrue(result.text.contains("- \"Triage\" (id: triage-main, task, pinned)"), result.text)
        XCTAssertTrue(result.text.contains("- \"Release chat\" (id: release-main, task, unpinned)"), result.text)
    }

    func testListThreadsOmitsIneligibleThreadsEntirely() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let archived = try fixture.insertTargetThread(name: "Archived", conversationID: "archived-main")
        archived.archivedAt = Date(timeIntervalSince1970: 10)
        let forkPending = try fixture.insertTargetThread(name: "Fork", conversationID: "fork-main")
        forkPending.isForkBootstrapPending = true
        let forked = try fixture.insertTargetThread(name: "Forked", conversationID: "forked-main")
        forked.conversations.append(Conversation(id: "forked-second-main", provider: "codex", thread: forked))
        let absorbingProject = Project(path: "/tmp/absorbing", name: "Absorbing")
        absorbingProject.isPinned = true
        let absorbed = try fixture.insertTargetThread(name: "Absorbed", conversationID: "absorbed-main")
        absorbed.project = absorbingProject
        absorbingProject.threads = [absorbed]
        fixture.modelContext.insert(absorbingProject)
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listThreadsToolName)
        )

        let threads = try array(try object(result.structuredContent)["threads"])
        XCTAssertEqual(try threads.map { try object($0)["id"] }, [.string(fixture.conversation.id)])
        // Nothing about an omitted thread reaches the provider, not even its name.
        let encodedResult = try encoded(result)
        for name in ["Archived", "Fork", "Forked", "Absorbed"] {
            XCTAssertFalse(encodedResult.contains(name), name)
        }
    }

    func testReadToolsRejectArgumentsAndNameThemselves() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()

        for toolName in ScheduledTaskHostToolCatalog.listToolNames.sorted() {
            let result = fixture.service.handle(
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

    /// Every read tool resolves the calling conversation first, so a caller whose conversation
    /// Alveary cannot resolve reads nothing — not the task list, not Project paths, not names.
    func testReadToolsRequireAUsableSourceConversation() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        fixture.thread.archivedAt = Date(timeIntervalSince1970: 10)
        try fixture.modelContext.save()

        for toolName in ScheduledTaskHostToolCatalog.listToolNames.sorted() {
            let result = fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(name: toolName)
            )

            XCTAssertTrue(result.isError, toolName)
        }
    }
}

extension ScheduledTaskHostToolFixture {
    @discardableResult
    func insertTargetThread(name: String, conversationID: String) throws -> AgentThread {
        let target = AgentThread(name: name, mode: .task)
        target.conversations = [Conversation(id: conversationID, provider: "codex", thread: target)]
        modelContext.insert(target)
        try modelContext.save()
        return target
    }
}
