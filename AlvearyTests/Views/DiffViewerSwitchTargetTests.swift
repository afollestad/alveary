import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class DiffViewerSwitchTargetTests: XCTestCase {
    func testForThreadReturnsNilWhenThreadHasNoProjectAndNoWorktree() throws {
        let fixture = try Fixture()
        let thread = AgentThread(name: "Thread")
        fixture.context.insert(thread)

        XCTAssertNil(DiffViewerSwitchTarget.forThread(thread))
    }

    func testForThreadUsesProjectPathAndBaseRefWhenNoWorktree() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(
            path: "/tmp/alveary-project",
            baseRef: "trunk",
            remoteName: "origin"
        )
        let thread = try fixture.insertThread(
            project: project,
            conversationIDs: ["conv-a", "conv-b"]
        )

        let target = try XCTUnwrap(DiffViewerSwitchTarget.forThread(thread))

        XCTAssertEqual(target.path, "/tmp/alveary-project")
        XCTAssertEqual(target.baseRef, "trunk")
        XCTAssertEqual(target.remoteName, "origin")
        XCTAssertEqual(target.conversationIds, ["conv-a", "conv-b"])
    }

    func testForThreadPrefersWorktreePathOverProjectPath() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project")
        let thread = try fixture.insertThread(
            project: project,
            worktreePath: "/tmp/alveary-worktree"
        )

        let target = try XCTUnwrap(DiffViewerSwitchTarget.forThread(thread))

        XCTAssertEqual(target.path, "/tmp/alveary-worktree")
    }

    func testForThreadDefaultsBaseRefToMainWhenProjectHasNone() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project", baseRef: nil)
        let thread = try fixture.insertThread(project: project)

        let target = try XCTUnwrap(DiffViewerSwitchTarget.forThread(thread))

        XCTAssertEqual(target.baseRef, "main")
    }

    func testForProjectIncludesOnlyNonWorktreeUnarchivedThreads() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project")
        _ = try fixture.insertThread(
            project: project,
            conversationIDs: ["project-thread-conv"]
        )
        _ = try fixture.insertThread(
            project: project,
            conversationIDs: ["worktree-thread-conv"],
            worktreePath: "/tmp/alveary-worktree"
        )
        _ = try fixture.insertThread(
            project: project,
            conversationIDs: ["archived-conv"],
            archivedAt: Date()
        )

        let target = DiffViewerSwitchTarget.forProject(project)

        XCTAssertEqual(target.path, "/tmp/alveary-project")
        XCTAssertEqual(target.conversationIds, ["project-thread-conv"])
    }

    func testForProjectIncludesThreadWhoseWorktreeMatchesProjectPath() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project")
        _ = try fixture.insertThread(
            project: project,
            conversationIDs: ["self-worktree-conv"],
            worktreePath: "/tmp/alveary-project"
        )

        let target = DiffViewerSwitchTarget.forProject(project)

        XCTAssertEqual(target.conversationIds, ["self-worktree-conv"])
    }

    func testForProjectCarriesRemoteAndBaseRefFromProject() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(
            path: "/tmp/alveary-project",
            baseRef: "develop",
            remoteName: "upstream"
        )

        let target = DiffViewerSwitchTarget.forProject(project)

        XCTAssertEqual(target.baseRef, "develop")
        XCTAssertEqual(target.remoteName, "upstream")
    }

    func testForProjectDefaultsBaseRefToMainWhenProjectHasNone() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project", baseRef: nil)

        let target = DiffViewerSwitchTarget.forProject(project)

        XCTAssertEqual(target.baseRef, "main")
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let context: ModelContext

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
    }

    func insertProject(
        path: String,
        baseRef: String? = nil,
        remoteName: String? = nil
    ) throws -> Project {
        let project = Project(
            path: path,
            name: (path as NSString).lastPathComponent,
            remoteName: remoteName,
            baseRef: baseRef
        )
        context.insert(project)
        try context.save()
        return project
    }

    @discardableResult
    func insertThread(
        project: Project,
        conversationIDs: [String] = [],
        worktreePath: String? = nil,
        archivedAt: Date? = nil
    ) throws -> AgentThread {
        let thread = AgentThread(
            name: "Thread",
            worktreePath: worktreePath,
            archivedAt: archivedAt,
            project: project
        )
        let conversations = conversationIDs.enumerated().map { index, id in
            Conversation(id: id, title: id, isMain: index == 0, displayOrder: index, thread: thread)
        }
        thread.conversations = conversations
        project.threads.append(thread)
        context.insert(thread)
        try context.save()
        return thread
    }
}
