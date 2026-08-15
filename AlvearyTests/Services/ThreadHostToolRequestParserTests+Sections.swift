import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolRequestParserTests {
    // MARK: - create_section

    func testCreateSectionReadsTheNameAndRejectsAnythingElse() throws {
        XCTAssertEqual(try sectionParser.parseCreateSection(arguments: ["name": .string("Research")]), "Research")

        XCTAssertThrowsError(try sectionParser.parseCreateSection(arguments: [:]))
        XCTAssertThrowsError(try sectionParser.parseCreateSection(arguments: ["name": .string("  ")]))
        XCTAssertThrowsError(
            try sectionParser.parseCreateSection(arguments: ["name": .string("Research"), "sort": .string("top")])
        )
    }

    // MARK: - move_thread_to_section

    func testMoveThreadToSectionRequiresBothFields() throws {
        let request = try sectionParser.parseMoveThreadToSection(arguments: [
            "thread_id": .string("triage-main"),
            "section": .string("Research")
        ])
        XCTAssertEqual(request, ThreadHostToolSectionMoveRequest(threadID: "triage-main", sectionName: "Research"))

        // Neither is optional: guessing either would silently move the wrong row.
        XCTAssertThrowsError(
            try sectionParser.parseMoveThreadToSection(arguments: ["thread_id": .string("triage-main")])
        )
        XCTAssertThrowsError(
            try sectionParser.parseMoveThreadToSection(arguments: ["section": .string("Research")])
        )
        XCTAssertThrowsError(
            try sectionParser.parseMoveThreadToSection(arguments: [
                "thread_id": .string("triage-main"),
                "section": .string("Research"),
                "pinned": .bool(true)
            ])
        )
    }

    // MARK: - create_thread's section

    func testCreateReadsASectionAsATaskPlacement() throws {
        let request = try sectionParser.parseCreate(arguments: ["section": .string("Research")])

        XCTAssertEqual(request.workspace, .task(grantedRoots: [], sectionName: "Research"))
    }

    func testCreateAcceptsASectionAlongsideTaskModeAndGrants() throws {
        let request = try sectionParser.parseCreate(arguments: [
            "section": .string("Research"),
            "mode": .string("task"),
            "granted_roots": .array([.string("/tmp/notes")])
        ])

        XCTAssertEqual(request.workspace, .task(grantedRoots: ["/tmp/notes"], sectionName: "Research"))
    }

    /// A section is where a *task* thread renders; a Project thread renders under its Project, so
    /// naming both describes two places at once.
    func testCreateRejectsASectionAlongsideAProjectPlacement() {
        XCTAssertThrowsError(
            try sectionParser.parseCreate(arguments: [
                "section": .string("Research"),
                "project_path": .string("/tmp/project")
            ])
        )
        XCTAssertThrowsError(
            try sectionParser.parseCreate(arguments: [
                "section": .string("Research"),
                "mode": .string("project")
            ])
        )
    }

    /// The retry hash covers every field that changes what gets created, and `section` changes
    /// where the thread lands — so two otherwise-identical requests must not share a receipt.
    func testTheCanonicalHashCoversTheSection() throws {
        let withSection = try sectionParser.parseCreate(arguments: [
            "mode": .string("task"),
            "section": .string("Research")
        ])
        let withOther = try sectionParser.parseCreate(arguments: [
            "mode": .string("task"),
            "section": .string("Reading")
        ])
        let withNone = try sectionParser.parseCreate(arguments: ["mode": .string("task")])

        XCTAssertNotEqual(withSection.canonicalPayloadHash, withOther.canonicalPayloadHash)
        XCTAssertNotEqual(withSection.canonicalPayloadHash, withNone.canonicalPayloadHash)
    }
}

private extension ThreadHostToolRequestParserTests {
    var sectionParser: ThreadHostToolRequestParser { ThreadHostToolRequestParser() }
}
