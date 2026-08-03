import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// Structural rules for the destination and workspace fields. Whether the named thread, Project,
/// or grant is actually usable is the service's job, covered in its own suite.
extension ScheduledTaskHostToolRequestParserTests {
    func testParsesExistingThreadDestination() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        var arguments = dailyCreateArguments()
        arguments["destination"] = .string("existing_thread")
        arguments["target_thread_id"] = .string("release-main")

        let parsed = try parser.parse(arguments: arguments)

        guard case .create(_, _, _, let placement) = parsed.request else {
            return XCTFail("Expected a create request")
        }
        XCTAssertEqual(placement, .existingThread(targetConversationID: "release-main"))
    }

    func testParsesWorkspaceWithoutAnExplicitDestination() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        var arguments = dailyCreateArguments()
        arguments["workspace"] = .object([
            "kind": .string("project"),
            "project_path": .string("/tmp/alveary"),
            "granted_roots": .array([.string("/tmp/notes")])
        ])

        let parsed = try parser.parse(arguments: arguments)

        guard case .create(_, _, _, let placement) = parsed.request else {
            return XCTFail("Expected a create request")
        }
        XCTAssertEqual(
            placement,
            .newThread(workspace: .project(path: "/tmp/alveary", grantedRoots: ["/tmp/notes"]))
        )
    }

    func testOmittedPlacementStaysInherited() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")

        let parsed = try parser.parse(arguments: dailyCreateArguments())

        guard case .create(_, _, _, let placement) = parsed.request else {
            return XCTFail("Expected a create request")
        }
        XCTAssertNil(placement)
    }

    func testRejectsIncoherentPlacementCombinations() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let privateWorkspace = AgentCLIKit.JSONValue.object(["kind": .string("private")])

        assertInvalid(
            placementArguments(["destination": .string("existing_thread")]),
            parser: parser,
            containing: "target_thread_id is required"
        )
        assertInvalid(
            placementArguments([
                "destination": .string("existing_thread"),
                "target_thread_id": .string("release-main"),
                "workspace": privateWorkspace
            ]),
            parser: parser,
            containing: "workspace does not apply"
        )
        assertInvalid(
            placementArguments([
                "destination": .string("new_thread"),
                "target_thread_id": .string("release-main")
            ]),
            parser: parser,
            containing: "only applies to an existing-thread destination"
        )
        assertInvalid(
            placementArguments(["target_thread_id": .string("release-main")]),
            parser: parser,
            containing: "requires destination existing_thread"
        )
        assertInvalid(
            placementArguments(["destination": .string("somewhere_else")]),
            parser: parser,
            containing: "must be new_thread or existing_thread"
        )
    }

    func testRejectsMalformedWorkspaces() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")

        assertInvalid(
            workspaceArguments(["kind": .string("project")]),
            parser: parser,
            containing: "project_path is required"
        )
        assertInvalid(
            workspaceArguments(["kind": .string("private"), "project_path": .string("/tmp/alveary")]),
            parser: parser,
            containing: "project_path does not apply"
        )
        assertInvalid(
            workspaceArguments(["kind": .string("elsewhere")]),
            parser: parser,
            containing: "must be project or private"
        )
        assertInvalid(
            workspaceArguments(["kind": .string("private"), "run_location": .string("local")]),
            parser: parser,
            containing: "unsupported field"
        )
        assertInvalid(
            workspaceArguments([
                "kind": .string("private"),
                "granted_roots": .array([.string("/tmp/notes"), .string("/tmp/notes")])
            ]),
            parser: parser,
            containing: "duplicate"
        )
        assertInvalid(
            workspaceArguments(["kind": .string("private"), "granted_roots": .array([.string("  ")])]),
            parser: parser,
            containing: "must not be empty"
        )
    }

    func testEditChangesAcceptPlacement() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let arguments: [String: AgentCLIKit.JSONValue] = [
            "action": .string("edit"),
            "task_id": .string("definition-1"),
            "revision": .number(2),
            "changes": .object([
                "destination": .string("existing_thread"),
                "target_thread_id": .string("release-main")
            ])
        ]

        let parsed = try parser.parse(arguments: arguments)

        guard case .edit(_, _, let changes) = parsed.request else {
            return XCTFail("Expected an edit request")
        }
        XCTAssertEqual(changes.placement, .existingThread(targetConversationID: "release-main"))
        XCTAssertNil(changes.title)
    }

    /// An edit's errors have to name the object the model actually sent.
    func testEditWorkspaceErrorsNameTheChangesPath() {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let arguments: [String: AgentCLIKit.JSONValue] = [
            "action": .string("edit"),
            "task_id": .string("definition-1"),
            "revision": .number(2),
            "changes": .object(["workspace": .object(["kind": .string("project")])])
        ]

        assertInvalid(arguments, parser: parser, containing: "arguments.changes.workspace.project_path")
    }

    /// Two proposals that differ only in where the task would run must not dedup into one
    /// replayed receipt, and reordered grants must not look like a different request.
    func testCanonicalPayloadDistinguishesPlacements() throws {
        let parser = ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC")
        let inherited = try parser.parse(arguments: dailyCreateArguments())
        let projectWorkspace = try parser.parse(
            arguments: workspaceArguments(["kind": .string("project"), "project_path": .string("/tmp/alveary")])
        )
        let otherProject = try parser.parse(
            arguments: workspaceArguments(["kind": .string("project"), "project_path": .string("/tmp/other")])
        )
        let hashes = [inherited, projectWorkspace, otherProject].map(\.canonicalPayloadHash)
        XCTAssertEqual(Set(hashes).count, 3)

        let firstOrder = try parser.parse(arguments: workspaceArguments([
            "kind": .string("private"),
            "granted_roots": .array([.string("/tmp/b"), .string("/tmp/a")])
        ]))
        let secondOrder = try parser.parse(arguments: workspaceArguments([
            "kind": .string("private"),
            "granted_roots": .array([.string("/tmp/a"), .string("/tmp/b")])
        ]))
        XCTAssertEqual(firstOrder.canonicalPayloadHash, secondOrder.canonicalPayloadHash)
    }
}

private extension ScheduledTaskHostToolRequestParserTests {
    func dailyCreateArguments() -> [String: AgentCLIKit.JSONValue] {
        [
            "action": .string("create"),
            "title": .string("Review"),
            "prompt": .string("Review changes."),
            "schedule": .object([
                "kind": .string("daily"),
                "hour": .number(9),
                "minute": .number(0)
            ])
        ]
    }

    func placementArguments(_ placement: [String: AgentCLIKit.JSONValue]) -> [String: AgentCLIKit.JSONValue] {
        dailyCreateArguments().merging(placement) { _, new in new }
    }

    func workspaceArguments(_ workspace: [String: AgentCLIKit.JSONValue]) -> [String: AgentCLIKit.JSONValue] {
        placementArguments(["workspace": .object(workspace)])
    }
}
