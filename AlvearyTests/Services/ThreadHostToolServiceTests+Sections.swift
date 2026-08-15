import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    // MARK: - create_section

    func testCreateSectionAddsOneAndReportsItsName() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.createSection(named: "Research")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("created"))
        XCTAssertEqual(content["section"], .string("Research"))
        XCTAssertEqual(
            try fixture.service.sectionService.orderedSections().map(\.name),
            ["Pinned", "Projects", "Tasks", "Research"]
        )
    }

    /// Idempotent by name, like `pin_thread`'s `already_pinned`: a replayed call is a success that
    /// changed nothing, which is why the tool keeps no receipt.
    func testCreateSectionIsIdempotentByNameIncludingBuiltins() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = await fixture.createSection(named: "Research")

        let duplicate = try object(await fixture.createSection(named: "research").structuredContent)
        XCTAssertEqual(duplicate["status"], .string("already_exists"))
        XCTAssertEqual(duplicate["section"], .string("Research"))

        let builtin = try object(await fixture.createSection(named: "tasks").structuredContent)
        XCTAssertEqual(builtin["status"], .string("already_exists"))
        XCTAssertEqual(builtin["section"], .string("Tasks"))

        XCTAssertEqual(try fixture.service.sectionService.orderedSections().count, 4)
    }

    // MARK: - move_thread_to_section

    func testMoveThreadToSectionMovesAndReportsTheSection() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        _ = await fixture.createSection(named: "Research")

        let result = await fixture.moveThread(threadID: "triage-main", toSection: "Research")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("moved"))
        XCTAssertEqual(content["thread_id"], .string("triage-main"))
        XCTAssertEqual(content["name"], .string("Triage"))
        XCTAssertEqual(content["section"], .string("Research"))
        XCTAssertEqual(target.customSection?.name, "Research")
    }

    func testMoveThreadToTasksClearsMembership() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        _ = await fixture.createSection(named: "Research")
        _ = await fixture.moveThread(threadID: "triage-main", toSection: "Research")

        let content = try object(
            await fixture.moveThread(threadID: "triage-main", toSection: "tasks").structuredContent
        )

        XCTAssertEqual(content["status"], .string("moved"))
        // Reported with the section's own spelling, not the caller's.
        XCTAssertEqual(content["section"], .string("Tasks"))
        XCTAssertNil(target.customSection)
    }

    func testMoveThreadReportsAlreadyInSectionWithoutChangingAnything() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        _ = await fixture.createSection(named: "Research")
        _ = await fixture.moveThread(threadID: "triage-main", toSection: "Research")

        let content = try object(
            await fixture.moveThread(threadID: "triage-main", toSection: "Research").structuredContent
        )

        XCTAssertEqual(content["status"], .string("already_in_section"))
        XCTAssertEqual(content["section"], .string("Research"))
    }

    /// A pinned thread renders above the sections, so the move unpins it rather than reporting a
    /// placement the sidebar would not show — the same refusal-to-lie `pin_thread` makes.
    func testMoveThreadUnpinsAPinnedThread() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        _ = await fixture.createSection(named: "Research")
        _ = await fixture.pinThread(threadID: "triage-main")
        XCTAssertTrue(target.isPinned)

        let result = await fixture.moveThread(threadID: "triage-main", toSection: "Research")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertFalse(target.isPinned)
        XCTAssertEqual(target.customSection?.name, "Research")
    }

    func testMoveThreadRefusesAnUnknownSectionAndNamesTheRealOnes() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = try fixture.insertThread(name: "Triage", conversationID: "triage-main")
        _ = await fixture.createSection(named: "Research")

        let result = await fixture.moveThread(threadID: "triage-main", toSection: "Reading")

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Reading"), result.text)
        XCTAssertTrue(result.text.contains("Tasks"), result.text)
        XCTAssertTrue(result.text.contains("Research"), result.text)
        XCTAssertTrue(result.text.contains("create_section"), result.text)
        // Mutating tools carry the status field their output schema promises.
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("error"))
    }

    /// `Pinned` and `Projects` are refused by name; `pin_thread` and a Project placement are the
    /// tools that put a thread in either.
    func testMoveThreadRefusesBuiltinSectionsThatAreNotTasks() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = try fixture.insertThread(name: "Triage", conversationID: "triage-main")

        for sectionName in ["Pinned", "Projects"] {
            let result = await fixture.moveThread(threadID: "triage-main", toSection: sectionName)
            XCTAssertTrue(result.isError, sectionName)
            XCTAssertTrue(result.text.contains("built-in"), result.text)
        }
    }

    func testMoveThreadRefusesAProjectPlacedThread() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = try fixture.insertThread(
            name: "Project mode",
            conversationID: "project-main",
            mode: .project,
            project: fixture.project
        )
        _ = await fixture.createSection(named: "Research")

        let result = await fixture.moveThread(threadID: "project-main", toSection: "Research")

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("task threads"), result.text)
    }

    // MARK: - create_thread's section

    func testCreateThreadPlacesTheNewThreadInAnExistingSection() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = await fixture.createSection(named: "Research")

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: ["section": .string("Research"), "name": .string("Spike")]
            )
        )

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("created"))
        XCTAssertEqual(content["section"], .string("Research"))
        XCTAssertEqual(content["workspace_kind"], .string("task"))
        let created = try XCTUnwrap(
            fixture.modelContext.resolveThread(conversationID: try threadID(in: content))
        )
        XCTAssertEqual(created.customSection?.name, "Research")
    }

    /// Agents compose `create_section` then `create_thread`; a typo must not silently mint a
    /// section, and must not leave a half-created thread behind either.
    func testCreateThreadRefusesAnUnknownSectionWithoutCreatingAnything() async throws {
        let fixture = try ThreadHostToolFixture()
        let threadCountBefore = try fixture.modelContext.fetchCount(FetchDescriptor<AgentThread>())

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: ["section": .string("Reading")]
            )
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("create_section"), result.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<AgentThread>()), threadCountBefore)
        XCTAssertEqual(try fixture.service.sectionService.orderedSections().count, 3)
    }

    func testCreateThreadRefusesASectionAlongsideAProjectPlacement() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = await fixture.createSection(named: "Research")

        for arguments: [String: AgentCLIKit.JSONValue] in [
            ["section": .string("Research"), "project_path": .string(fixture.project.path)],
            ["section": .string("Research"), "mode": .string("project")]
        ] {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(
                    name: ThreadHostToolCatalog.createThreadToolName,
                    arguments: arguments
                )
            )
            XCTAssertTrue(result.isError, "\(arguments)")
        }
    }

    /// `Tasks` is a placement a caller may legitimately name; it means the ordinary Task section,
    /// so the thread is created with no membership rather than refused.
    func testCreateThreadAcceptsTasksAsAnExplicitSection() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: ["section": .string("Tasks")]
            )
        )

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["section"], .string("Tasks"))
        let created = try XCTUnwrap(
            fixture.modelContext.resolveThread(conversationID: try threadID(in: content))
        )
        XCTAssertNil(created.customSection)
    }

    // MARK: - list_threads

    func testListThreadsReportsEachThreadsSection() async throws {
        let fixture = try ThreadHostToolFixture()
        _ = try fixture.insertThread(name: "Member", conversationID: "member-main")
        _ = try fixture.insertThread(name: "Plain", conversationID: "plain-main")
        _ = try fixture.insertThread(
            name: "In project",
            conversationID: "project-main",
            mode: .project,
            project: fixture.project
        )
        _ = await fixture.createSection(named: "Research")
        _ = await fixture.moveThread(threadID: "member-main", toSection: "Research")

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listThreadsToolName)
        )

        let rows = try sectionsByThreadID(in: result)
        XCTAssertEqual(rows["member-main"], "Research")
        XCTAssertEqual(rows["plain-main"], "Tasks")
        // A Project thread renders under its Project, so it reports no section at all.
        XCTAssertNil(rows["project-main"])
    }
}

private extension ThreadHostToolServiceTests {
    func sectionsByThreadID(in result: AgentCLIKit.AgentHostToolResult) throws -> [String: String] {
        let content = try object(result.structuredContent)
        guard case .array(let threads)? = content["threads"] else {
            return [:]
        }
        var sections: [String: String] = [:]
        for thread in threads {
            let row = try object(thread)
            guard case .string(let id)? = row["id"], case .string(let section)? = row["section"] else {
                continue
            }
            sections[id] = section
        }
        return sections
    }

    func threadID(in content: [String: AgentCLIKit.JSONValue]) throws -> String {
        guard case .string(let threadID)? = content["thread_id"] else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        return threadID
    }
}

extension ThreadHostToolFixture {
    func createSection(named name: String) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createSectionToolName,
                arguments: ["name": .string(name)]
            )
        )
    }

    func moveThread(threadID: String, toSection sectionName: String) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.moveThreadToSectionToolName,
                arguments: ["thread_id": .string(threadID), "section": .string(sectionName)]
            )
        )
    }
}
