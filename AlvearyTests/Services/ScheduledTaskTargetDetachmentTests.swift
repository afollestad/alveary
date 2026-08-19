import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A schedule survives losing the thread it was aimed at: the lifecycle commit converts it to the
/// self-healing reuse mode and hands it the closest workspace the vanishing thread can describe.
@MainActor
final class ScheduledTaskTargetDetachmentTests: XCTestCase {
    func testProjectModeTargetHandsOverItsProjectAndRunLocation() throws {
        let context = try makeContext()
        let project = Project(path: "/tmp/detach-project", name: "Detach")
        let thread = AgentThread(name: "Release chat", useWorktree: true, project: project)
        let definition = makeDefinition(targetThread: thread)
        project.threads = [thread]
        context.insert(project)
        context.insert(definition)
        try context.save()
        let revisionBeforeDetach = definition.revision

        let changed = ScheduledTaskTargetDetachment.detachTargets(
            of: thread,
            at: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(changed, [definition.id])
        XCTAssertEqual(definition.decodedDestination, ScheduledTaskDestination.reusedThread)
        XCTAssertNil(definition.targetThread)
        XCTAssertNil(definition.reusedThread)
        XCTAssertEqual(definition.workspaceKind, ScheduledTaskWorkspaceKind.project)
        XCTAssertEqual(definition.project?.path, "/tmp/detach-project")
        XCTAssertEqual(definition.workspaceStrategy, ScheduledTaskWorkspaceStrategy.worktree)
        XCTAssertEqual(definition.grantedRoots, [])
        XCTAssertNil(definition.threadSection)
        XCTAssertEqual(definition.state, ScheduledTaskState.active)
        XCTAssertEqual(definition.revision, revisionBeforeDetach + 1)
        XCTAssertEqual(definition.modifiedAt, Date(timeIntervalSince1970: 5_000))
    }

    func testProjectModeTargetWithoutAWorktreeHandsOverALocalCheckout() throws {
        let context = try makeContext()
        let project = Project(path: "/tmp/detach-local", name: "Local")
        let thread = AgentThread(name: "Local chat", project: project)
        let definition = makeDefinition(targetThread: thread)
        project.threads = [thread]
        context.insert(project)
        context.insert(definition)
        try context.save()

        ScheduledTaskTargetDetachment.detachTargets(of: thread)

        XCTAssertEqual(definition.workspaceStrategy, ScheduledTaskWorkspaceStrategy.localCheckout)
    }

    /// A Task's `primaryRoot` is the workspace being torn down, so only its grants carry over.
    func testTaskTargetHandsOverItsGrantedRootsAndSection() throws {
        let context = try makeContext()
        let section = SidebarSection(id: "chores", kind: .custom, name: "Chores", sortOrder: 3)
        let thread = AgentThread(
            name: "Chore chat",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/detach-task-primary",
                grantedRoots: ["/tmp/detach-grant-a", "/tmp/detach-grant-b"],
                ownershipStrategy: .privateOwned
            )
        )
        thread.customSection = section
        let definition = makeDefinition(targetThread: thread)
        context.insert(section)
        context.insert(thread)
        context.insert(definition)
        try context.save()

        ScheduledTaskTargetDetachment.detachTargets(of: thread)

        XCTAssertEqual(definition.workspaceKind, ScheduledTaskWorkspaceKind.privateWorkspace)
        XCTAssertNil(definition.project)
        XCTAssertEqual(definition.grantedRoots, ["/tmp/detach-grant-a", "/tmp/detach-grant-b"])
        XCTAssertFalse(definition.grantedRoots.contains("/tmp/detach-task-primary"))
        XCTAssertEqual(definition.threadSection?.id, "chores")
    }

    /// `CanonicalPath.normalize` resolves symlinks, so re-canonicalizing an inherited grant would
    /// move the user's authorization boundary to whatever the link now points at. The persisted
    /// string has to survive verbatim.
    func testTaskTargetGrantsAreCopiedWithoutResolvingSymlinks() throws {
        let context = try makeContext()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-detach-symlink-\(UUID().uuidString)", isDirectory: true)
        let target = root.appendingPathComponent("Real", isDirectory: true)
        let link = root.appendingPathComponent("Link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: root) }
        // Sanity: this is a path canonicalization would rewrite.
        XCTAssertNotEqual(CanonicalPath.normalize(link.path), link.path)

        let thread = AgentThread(
            name: "Symlinked grant",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                persistedPrimaryRoot: "/tmp/detach-symlink-primary",
                persistedGrantedRoots: [link.path],
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: nil,
                persistedSourceProjectPath: nil
            )
        )
        let definition = makeDefinition(targetThread: thread)
        context.insert(thread)
        context.insert(definition)
        try context.save()

        ScheduledTaskTargetDetachment.detachTargets(of: thread)

        XCTAssertEqual(definition.grantedRoots, [link.path])
    }

    /// `.project` mode with no Project cannot name one, so it takes the private-workspace shape
    /// rather than persisting a kind nothing can satisfy.
    func testProjectModeTargetWithoutAProjectFallsBackToAPrivateWorkspace() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Orphan")
        let definition = makeDefinition(targetThread: thread)
        context.insert(thread)
        context.insert(definition)
        try context.save()

        ScheduledTaskTargetDetachment.detachTargets(of: thread)

        XCTAssertEqual(definition.workspaceKind, ScheduledTaskWorkspaceKind.privateWorkspace)
        XCTAssertNil(definition.project)
        XCTAssertEqual(definition.grantedRoots, [])
    }

    func testProjectDeletionPausesInsteadOfInheritingTheDoomedProject() throws {
        let context = try makeContext()
        let project = Project(path: "/tmp/detach-doomed", name: "Doomed")
        let thread = AgentThread(
            name: "Doomed task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/detach-doomed-primary",
                grantedRoots: ["/tmp/detach-doomed", "/tmp/detach-survivor"],
                ownershipStrategy: .privateOwned
            ),
            project: project
        )
        let definition = makeDefinition(targetThread: thread)
        project.threads = [thread]
        context.insert(project)
        context.insert(definition)
        try context.save()

        ScheduledTaskTargetDetachment.detachTargets(
            of: thread,
            continuation: .pauseForProjectDeletion(projectPath: "/tmp/detach-doomed"),
            at: Date(timeIntervalSince1970: 6_000)
        )

        XCTAssertEqual(definition.decodedDestination, ScheduledTaskDestination.reusedThread)
        XCTAssertEqual(definition.state, ScheduledTaskState.paused)
        XCTAssertEqual(definition.pauseReason, ScheduledTask.projectDeletedPauseReason)
        XCTAssertNil(definition.project)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertEqual(definition.grantedRoots, ["/tmp/detach-survivor"])
        XCTAssertEqual(definition.modifiedAt, Date(timeIntervalSince1970: 6_000))
    }

    func testAThreadNoScheduleTargetsIsLeftAlone() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Unattached", mode: .task)
        context.insert(thread)
        try context.save()

        XCTAssertEqual(ScheduledTaskTargetDetachment.detachTargets(of: thread), [])
        XCTAssertFalse(context.hasChanges)
    }

    /// The undecodable raw value is what makes the scheduler pause the definition rather than run
    /// it. Rewriting it to `.reusedThread` would hand a forward-version row a workspace.
    func testAnUnknownDestinationKeepsItsRawValueAndIsNotConverted() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Future target", mode: .task)
        let definition = makeDefinition(targetThread: thread)
        definition.destinationRawValue = "future-destination"
        context.insert(thread)
        context.insert(definition)
        try context.save()

        XCTAssertEqual(ScheduledTaskTargetDetachment.detachTargets(of: thread), [])

        XCTAssertNil(definition.decodedDestination)
        XCTAssertEqual(definition.destinationRawValue, "future-destination")
        XCTAssertEqual(definition.targetThread?.persistentModelID, thread.persistentModelID)
    }

    /// A per-run schedule ignores `targetThread` outright, so a stray link is not a reason to
    /// change what the definition does.
    func testANewThreadPerRunDefinitionIsNotConverted() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Stray link", mode: .task)
        let definition = makeDefinition(targetThread: thread)
        definition.destination = .newThreadPerRun
        context.insert(thread)
        context.insert(definition)
        try context.save()

        XCTAssertEqual(ScheduledTaskTargetDetachment.detachTargets(of: thread), [])

        XCTAssertEqual(definition.decodedDestination, ScheduledTaskDestination.newThreadPerRun)
    }

    /// A reuse thread is the schedule's own, so it is never in `targetedScheduledTasks` and the
    /// materializer's self-heal — not this — is what replaces it.
    func testAReuseLinkIsNotDetached() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Rolling", mode: .task)
        let definition = makeDefinition(targetThread: nil)
        definition.destination = .reusedThread
        definition.reusedThread = thread
        context.insert(thread)
        context.insert(definition)
        try context.save()

        XCTAssertEqual(ScheduledTaskTargetDetachment.detachTargets(of: thread), [])
        XCTAssertEqual(definition.reusedThread?.persistentModelID, thread.persistentModelID)
    }
}

private extension ScheduledTaskTargetDetachmentTests {
    func makeContext() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: Project.self,
                AgentThread.self,
                SidebarSection.self,
                Conversation.self,
                ConversationEventRecord.self,
                ScheduledTask.self,
                ScheduledTaskRun.self,
                ScheduledTaskProposal.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    func makeDefinition(targetThread: AgentThread?) -> ScheduledTask {
        ScheduledTask(
            title: "Nightly sweep",
            prompt: "Sweep the release branch.",
            destination: targetThread == nil ? .newThreadPerRun : .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            nextOccurrenceAt: Date(timeIntervalSince1970: 9_000),
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100),
            targetThread: targetThread
        )
    }
}
