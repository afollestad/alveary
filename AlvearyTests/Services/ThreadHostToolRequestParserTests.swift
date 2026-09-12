import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class ThreadHostToolRequestParserTests: XCTestCase {
    private let parser = ThreadHostToolRequestParser()

    func testCreateReadsEverySupportedField() throws {
        let request = try parser.parseCreate(arguments: [
            "project_path": .string("/tmp/project"),
            "name": .string("Release checklist"),
            "provider": .string("codex"),
            "model": .string("gpt-5"),
            "effort": .string("high"),
            "permission_mode": .string("never"),
            "initial_prompt": .string("Audit the notes."),
            "pinned": .bool(true)
        ])

        XCTAssertEqual(request.workspace, .project(path: "/tmp/project"))
        XCTAssertEqual(request.name, "Release checklist")
        XCTAssertEqual(request.provider, "codex")
        XCTAssertEqual(request.model, "gpt-5")
        XCTAssertEqual(request.effort, "high")
        XCTAssertEqual(request.permissionMode, "never")
        XCTAssertEqual(request.initialPrompt, "Audit the notes.")
        XCTAssertEqual(request.pinned, true)
    }

    func testCreateRejectsUnknownKeysAndWrongTypes() {
        assertInvalid(
            ["project_path": .string("/tmp/project"), "workspace": .string("private")],
            containing: "unsupported field(s): workspace"
        )
        assertInvalid(
            ["project_path": .string("/tmp/project"), "pinned": .string("yes")],
            containing: "arguments.pinned must be a boolean."
        )
        assertInvalid(
            ["project_path": .number(7)],
            containing: "arguments.project_path must be a string."
        )
    }

    /// A blank optional field is the same call as one that omits it, so a blank `project_path`
    /// names no placement and inherits the caller's — and still cannot stand in for the one a
    /// project thread requires.
    func testABlankProjectPathNamesNoPlacement() throws {
        XCTAssertEqual(
            try parser.parseCreate(arguments: ["project_path": .string("   ")]).workspace,
            .inherit(grantedRoots: nil)
        )
        assertInvalid(
            ["mode": .string("project"), "project_path": .string("   ")],
            containing: "project_id is required for a project selection."
        )
    }

    /// Naming no placement is not an error: the handler resolves it against the calling thread,
    /// which the parser cannot see.
    func testCreateReadsEachWorkspacePlacement() throws {
        XCTAssertEqual(
            try parser.parseCreate(arguments: ["mode": .string("task")]).workspace,
            .task(grantedRoots: nil)
        )
        XCTAssertEqual(
            try parser.parseCreate(arguments: [
                "mode": .string("project"),
                "project_path": .string("/tmp/project")
            ]).workspace,
            .project(path: "/tmp/project")
        )
        XCTAssertEqual(try parser.parseCreate(arguments: [:]).workspace, .inherit(grantedRoots: nil))

        assertInvalid(["mode": .string("project")], containing: "project_id is required")
        XCTAssertEqual(
            try parser.parseCreate(arguments: ["mode": .string("task"), "project_id": .string("project-1")]).workspace,
            .project(path: "project-1", isID: true, privateWorkspace: true)
        )
        assertInvalid(["mode": .string("worktree")], containing: "arguments.mode must be project or task.")
    }

    func testCreateReadsGrantedRootsForEveryWorkspace() throws {
        XCTAssertEqual(
            try parser.parseCreate(arguments: [
                "mode": .string("task"),
                "granted_roots": .array([.string("/tmp/one"), .string("  /tmp/two  ")])
            ]).workspace,
            .task(grantedRoots: ["/tmp/one", "/tmp/two"])
        )
        // An explicit grant list replaces the saved grants in either execution kind.
        XCTAssertEqual(
            try parser.parseCreate(arguments: [
                "granted_roots": .array([.string("/tmp/one")])
            ]).workspace,
            .inherit(grantedRoots: ["/tmp/one"])
        )

        XCTAssertEqual(
            try parser.parseCreate(arguments: [
                "project_path": .string("/tmp/project"), "granted_roots": .array([.string("/tmp/one")])
            ]).workspace,
            .project(path: "/tmp/project", grantedRoots: ["/tmp/one"])
        )
        assertInvalid(
            ["mode": .string("task"), "granted_roots": .string("/tmp/one")],
            containing: "arguments.granted_roots must be an array."
        )
        assertInvalid(
            ["mode": .string("task"), "granted_roots": .array([.number(7)])],
            containing: "arguments.granted_roots[0] must be a string."
        )
        assertInvalid(
            ["mode": .string("task"), "granted_roots": .array([.string("   ")])],
            containing: "arguments.granted_roots[0] must not be empty."
        )
        assertInvalid(
            ["mode": .string("task"), "granted_roots": .array([.string("/tmp/one"), .string("/tmp/one")])],
            containing: "arguments.granted_roots must not contain duplicate paths."
        )
    }

    /// The dedup key is what stops a replay from creating a second thread, so the hash has to be
    /// stable across argument order and sensitive to every field that changes the result.
    func testTheCanonicalHashIsOrderStableAndFieldSensitive() throws {
        let base: [String: AgentCLIKit.JSONValue] = [
            "project_path": .string("/tmp/project"),
            "name": .string("Release checklist"),
            "pinned": .bool(true)
        ]
        let reordered: [String: AgentCLIKit.JSONValue] = [
            "pinned": .bool(true),
            "name": .string("Release checklist"),
            "project_path": .string("/tmp/project")
        ]

        let baseHash = try parser.parseCreate(arguments: base).canonicalPayloadHash
        XCTAssertEqual(try parser.parseCreate(arguments: reordered).canonicalPayloadHash, baseHash)

        for changed in [
            base.merging(["name": .string("Other")]) { _, new in new },
            base.merging(["pinned": .bool(false)]) { _, new in new },
            base.merging(["initial_prompt": .string("Go")]) { _, new in new },
            base.merging(["provider": .string("codex")]) { _, new in new }
        ] {
            XCTAssertNotEqual(try parser.parseCreate(arguments: changed).canonicalPayloadHash, baseHash)
        }
    }

    /// Where a thread lives is part of what a retry is a retry of, so two requests that differ
    /// only in placement or grants must not collapse into one replayed receipt.
    func testTheCanonicalHashCoversPlacementAndGrants() throws {
        let task: [String: AgentCLIKit.JSONValue] = [
            "mode": .string("task"),
            "granted_roots": .array([.string("/tmp/one"), .string("/tmp/two")])
        ]
        let taskHash = try parser.parseCreate(arguments: task).canonicalPayloadHash

        // Granting the same folders in another order is the same request.
        XCTAssertEqual(
            try parser.parseCreate(arguments: [
                "mode": .string("task"),
                "granted_roots": .array([.string("/tmp/two"), .string("/tmp/one")])
            ]).canonicalPayloadHash,
            taskHash
        )

        for changed: [String: AgentCLIKit.JSONValue] in [
            ["mode": .string("task")],
            ["mode": .string("task"), "granted_roots": .array([.string("/tmp/one")])],
            ["project_path": .string("/tmp/project")],
            ["mode": .string("project"), "project_path": .string("/tmp/project")],
            // An inherited placement, which resolves to a task thread for a task caller.
            [:]
        ] {
            XCTAssertNotEqual(try parser.parseCreate(arguments: changed).canonicalPayloadHash, taskHash)
        }
    }

    /// An omitted field and an explicitly supplied one are different requests: the receipt records
    /// what was asked for, not what it resolved to.
    func testAnOmittedFieldHashesDifferentlyFromAnExplicitOne() throws {
        let omitted = try parser.parseCreate(arguments: ["project_path": .string("/tmp/project")])
        let explicit = try parser.parseCreate(arguments: [
            "project_path": .string("/tmp/project"),
            "pinned": .bool(false)
        ])

        XCTAssertNotEqual(omitted.canonicalPayloadHash, explicit.canonicalPayloadHash)
    }

    func testArchiveReadsTheThreadIdentifierAndRejectsAnythingElse() throws {
        XCTAssertEqual(try parser.parseArchive(arguments: ["thread_id": .string("target-main")]), "target-main")

        XCTAssertThrowsError(
            try parser.parseArchive(arguments: ["thread_id": .string("target-main"), "force": .bool(true)])
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("unsupported field(s): force"),
                error.localizedDescription
            )
        }
        XCTAssertThrowsError(try parser.parseArchive(arguments: [:]))
    }

    func testProjectFolderSelectionAndRootRemovalHaveDistinctRetryIdentities() throws {
        let base: [String: AgentCLIKit.JSONValue] = ["project_id": .string("first")]
        let original = try parser.parseCreate(arguments: base).canonicalPayloadHash
        let variants: [[String: AgentCLIKit.JSONValue]] = [
            ["project_id": .string("second")],
            base.merging(["primary_folder_path": .string("/tmp/secondary")]) { _, new in new },
            base.merging(["granted_roots": .array([])]) { _, new in new }
        ]
        for arguments in variants {
            XCTAssertNotEqual(try parser.parseCreate(arguments: arguments).canonicalPayloadHash, original)
        }
        assertInvalid(["project_id": .string("first"), "project_path": .string("/tmp/source")], containing: "not both")
        assertInvalid(["primary_folder_path": .string("/tmp/source")], containing: "requires project_id")
    }

    private func assertInvalid(
        _ arguments: [String: AgentCLIKit.JSONValue],
        containing expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parser.parseCreate(arguments: arguments), file: file, line: line) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(expected),
                error.localizedDescription,
                file: file,
                line: line
            )
        }
    }
}
