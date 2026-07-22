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
        XCTAssertEqual(target.projectPath, "/tmp/alveary-project")
        XCTAssertNil(target.worktreePath)
        XCTAssertEqual(target.directory, "/tmp/alveary-project")
        XCTAssertEqual(target.baseRef, "trunk")
        XCTAssertEqual(target.remoteName, "origin")
        XCTAssertEqual(target.conversationIds, ["conv-a", "conv-b"])
    }

    func testForThreadUsesCandidateConversationIDsWhenProvided() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project")
        let thread = try fixture.insertThread(
            project: project,
            conversationIDs: ["relationship-conv"]
        )

        let target = try XCTUnwrap(DiffViewerSwitchTarget.forThread(
            thread,
            candidateConversationIDs: ["fetched-conv"]
        ))

        XCTAssertEqual(target.conversationIds, ["fetched-conv"])
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
        XCTAssertEqual(target.projectPath, "/tmp/alveary-project")
        XCTAssertEqual(target.worktreePath, "/tmp/alveary-worktree")
        XCTAssertEqual(target.directory, "/tmp/alveary-worktree")
    }

    func testForThreadDefaultsBaseRefToMainWhenProjectHasNone() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project", baseRef: nil)
        let thread = try fixture.insertThread(project: project)

        let target = try XCTUnwrap(DiffViewerSwitchTarget.forThread(thread))

        XCTAssertEqual(target.baseRef, "main")
    }

    func testForThreadUsesProjectSnapshotForLinkedRunWithFallbackMode() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/fallback-scheduled-project")
        let thread = try fixture.insertThread(
            project: project,
            conversationIDs: ["fallback-scheduled-conversation"],
            worktreePath: "/tmp/fallback-scheduled-worktree"
        )
        thread.modeRawValue = "future-mode"
        let run = makeDiffViewerScheduledRun()
        run.thread = thread
        thread.scheduledTaskRun = run
        fixture.context.insert(run)
        try fixture.context.save()

        let target = try XCTUnwrap(DiffViewerSwitchTarget.forThread(thread))

        XCTAssertEqual(target.projectPath, project.path)
        XCTAssertEqual(target.worktreePath, thread.worktreePath)
        XCTAssertEqual(target.directory, thread.worktreePath)
        XCTAssertEqual(target.conversationIds, ["fallback-scheduled-conversation"])
    }

    func testForThreadDoesNotExposeProjectRootForPrivateLinkedRunWithFallbackMode() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/fallback-private-project")
        let thread = try fixture.insertThread(
            project: project,
            conversationIDs: ["fallback-private-conversation"],
            worktreePath: "/tmp/fallback-private-worktree"
        )
        thread.modeRawValue = "future-mode"
        let run = makeDiffViewerScheduledRun(workspaceKind: .privateWorkspace)
        run.thread = thread
        thread.scheduledTaskRun = run
        fixture.context.insert(run)
        try fixture.context.save()

        XCTAssertNil(DiffViewerSwitchTarget.forThread(thread))
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
        XCTAssertEqual(target.projectPath, "/tmp/alveary-project")
        XCTAssertNil(target.worktreePath)
        XCTAssertEqual(target.directory, "/tmp/alveary-project")
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

    func testForProjectUsesWorkspaceSnapshotForLinkedRunsWithFallbackMode() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project")
        _ = try fixture.insertThread(project: project, conversationIDs: ["project-conversation"])
        let projectFallback = try fixture.insertThread(project: project, conversationIDs: ["project-fallback-conversation"])
        projectFallback.modeRawValue = "future-mode"
        let projectRun = makeDiffViewerScheduledRun()
        projectRun.thread = projectFallback
        projectFallback.scheduledTaskRun = projectRun
        fixture.context.insert(projectRun)
        let privateFallback = try fixture.insertThread(project: project, conversationIDs: ["private-fallback-conversation"])
        privateFallback.modeRawValue = "future-mode"
        let privateRun = makeDiffViewerScheduledRun(workspaceKind: .privateWorkspace)
        privateRun.thread = privateFallback
        privateFallback.scheduledTaskRun = privateRun
        fixture.context.insert(privateRun)
        try fixture.context.save()

        let target = DiffViewerSwitchTarget.forProject(project)

        XCTAssertEqual(target.conversationIds, ["project-conversation", "project-fallback-conversation"])
    }

    func testForProjectUsesCandidateConversationIDsWhenProvided() throws {
        let fixture = try Fixture()
        let project = try fixture.insertProject(path: "/tmp/alveary-project")
        _ = try fixture.insertThread(
            project: project,
            conversationIDs: ["relationship-conv"]
        )

        let target = DiffViewerSwitchTarget.forProject(
            project,
            candidateThreads: [],
            candidateConversationIDs: ["fetched-conv"]
        )

        XCTAssertEqual(target.conversationIds, ["fetched-conv"])
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

private func makeDiffViewerScheduledRun(
    workspaceKind: ScheduledTaskWorkspaceKind = .project
) -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "diff-viewer-definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
        triggerKind: .scheduled,
        status: .success,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "UTC",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: workspaceKind,
        workspaceStrategySnapshot: .worktree
    )
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
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
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
