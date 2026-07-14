import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskSchedulerEngineTests: XCTestCase {
    func testClaimRunsPreflightAndPersistsImmutableSnapshotBeforeAdvancingCadence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let project = Project(
            path: "/tmp/scheduler-project",
            name: "Scheduler Project",
            remoteName: "upstream",
            baseRef: "main"
        )
        fixture.context.insert(project)
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300),
            project: project,
            grantedRoots: ["/tmp/grant/../grant"]
        )
        var capturedSnapshot: ScheduledTaskPreflightSnapshot?
        let engine = fixture.makeEngine { snapshot in
            capturedSnapshot = snapshot
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(660)
        )

        guard case let .claimed(runID) = result else {
            return XCTFail("Expected the latest occurrence to be claimed")
        }
        let run = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertEqual(run.occurrenceAt, fixture.date(600))
        XCTAssertEqual(run.status, .claimed)
        XCTAssertEqual(run.definitionRevision, 1)
        XCTAssertEqual(run.projectPathSnapshot, CanonicalPath.normalize(project.path))
        XCTAssertEqual(run.projectBaseRefSnapshot, "main")
        XCTAssertEqual(run.projectRemoteNameSnapshot, "upstream")
        XCTAssertEqual(run.grantedRootsSnapshot, [CanonicalPath.normalize("/tmp/grant")])
        XCTAssertEqual(
            run.workspaceIdentitySnapshot,
            capturedSnapshot.map(scheduledTaskTestWorkspaceIdentities(for:))
        )
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(900))
        XCTAssertEqual(capturedSnapshot?.scheduledOccurrenceAt, fixture.date(600))
        XCTAssertEqual(capturedSnapshot?.providerID, "codex")
        XCTAssertEqual(capturedSnapshot?.model, "gpt-5")
        XCTAssertEqual(capturedSnapshot?.effort, "high")
        XCTAssertEqual(capturedSnapshot?.permissionMode, "acceptEdits")
        XCTAssertEqual(capturedSnapshot?.workspaceKind, .project)
        XCTAssertEqual(capturedSnapshot?.workspaceStrategy, .worktree)
        XCTAssertEqual(capturedSnapshot?.projectPath, CanonicalPath.normalize(project.path))
        XCTAssertEqual(capturedSnapshot?.projectBaseRef, "main")
        XCTAssertEqual(capturedSnapshot?.projectRemoteName, "upstream")
        XCTAssertEqual(capturedSnapshot?.grantedRoots, [CanonicalPath.normalize("/tmp/grant")])
    }

    func testSuccessfulOneShotClaimCompletesDefinition() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(300)
        let definition = try fixture.insertDefinition(
            recurrence: .once(occurrence),
            nextOccurrenceAt: occurrence
        )

        let result = try await fixture.makeEngine().claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case .claimed = result else {
            return XCTFail("Expected the one-shot occurrence to be claimed")
        }
        XCTAssertEqual(definition.state, .completed)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testInvalidOneShotPreflightPausesWithoutClaimingOrCompleting() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(300)
        let definition = try fixture.insertDefinition(
            recurrence: .once(occurrence),
            nextOccurrenceAt: occurrence
        )
        let engine = fixture.makeEngine { _ in
            .invalid(reason: "Provider is unavailable.")
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected invalid preflight to pause the definition")
        }
        XCTAssertEqual(reason, "Provider is unavailable.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertEqual(definition.pauseReason, reason)
        XCTAssertEqual(definition.lastError, reason)
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testUnavailablePinnedWorktreeBasePausesOneShotWithoutClaimingOrCompleting() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(300)
        let project = Project(
            path: "/tmp/unavailable-pinned-base",
            name: "Pinned Base",
            remoteName: "upstream",
            baseRef: "release/missing"
        )
        fixture.context.insert(project)
        let definition = try fixture.insertDefinition(
            recurrence: .once(occurrence),
            nextOccurrenceAt: occurrence,
            project: project
        )
        let expectedProjectPath = CanonicalPath.normalize(project.path)
        let expectedReason = "The scheduled task worktree cannot be created: Pinned base release/missing is unavailable."
        let validator = makeUnavailablePinnedBaseValidator(expectedProjectPath: expectedProjectPath)
        var preflightOutcome: ScheduledTaskPreflightOutcome?
        let engine = fixture.makeEngine { snapshot in
            let outcome = await validator.validate(snapshot)
            preflightOutcome = outcome
            return outcome
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected unavailable pinned base to pause the one-shot")
        }
        XCTAssertEqual(preflightOutcome, .invalid(reason: expectedReason))
        XCTAssertEqual(reason, expectedReason)
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testInvalidDueIntervalPausesInsteadOfThrowing() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 0, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(0)
        )

        let result = try await fixture.makeEngine().claimDue(
            definitionID: definition.id,
            at: fixture.date(60)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected malformed due recurrence to pause")
        }
        XCTAssertTrue(reason.contains("Intervals must be at least"))
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testInvalidTimezoneWithNoOccurrencePausesInsteadOfRemainingActive() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: nil)
        definition.timeZoneIdentifier = "invalid/timezone"
        try fixture.context.save()

        let result = try await fixture.makeEngine().claimDue(
            definitionID: definition.id,
            at: fixture.date(60)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected malformed timezone to pause")
        }
        XCTAssertTrue(reason.contains("Unknown IANA time zone"))
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testActiveDefinitionWithValidRecurrenceButNoOccurrencePausesInsteadOfSpinning() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: nil)

        let result = try await fixture.makeEngine().claimDue(
            definitionID: definition.id,
            at: fixture.date(60)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected missing occurrence state to pause")
        }
        XCTAssertEqual(reason, "Scheduled task next occurrence is missing.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(28_800))
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testDefinitionRevisionIsRecheckedAfterAsyncPreflight() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        let engine = fixture.makeEngine { snapshot in
            definition.revision += 1
            definition.title = "Edited during preflight"
            try? fixture.context.save()
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case .changedDuringPreflight = result else {
            return XCTFail("Expected the stale claim to be discarded")
        }
        XCTAssertEqual(definition.title, "Edited during preflight")
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(300))
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testProjectWorktreeConfigurationIsRecheckedAfterAsyncPreflight() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let project = Project(
            path: "/tmp/project-configuration-race",
            name: "Project",
            remoteName: "upstream",
            baseRef: "main"
        )
        fixture.context.insert(project)
        let definition = try fixture.insertDefinition(
            nextOccurrenceAt: fixture.date(300),
            project: project
        )
        let engine = fixture.makeEngine { snapshot in
            project.baseRef = "develop"
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case .changedDuringPreflight = result else {
            return XCTFail("Expected Project configuration changes to invalidate preflight")
        }
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testActiveRunCoalescesLatestOverlapAndAdvancesCadence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        try fixture.insertRun(definition: definition, status: .running, occurrenceAt: fixture.date(0))

        let result = try await fixture.makeEngine().claimDue(
            definitionID: definition.id,
            at: fixture.date(1_000)
        )

        guard case let .overlapped(pendingOccurrenceAt) = result else {
            return XCTFail("Expected overlap to be coalesced")
        }
        XCTAssertEqual(pendingOccurrenceAt, fixture.date(900))
        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.date(900))
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(1_200))
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testPendingOccurrenceIsClaimedAfterActiveRunFinishesWithoutShiftingCadence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(1_200),
            pendingOccurrenceAt: fixture.date(900)
        )
        try fixture.insertRun(definition: definition, status: .success, occurrenceAt: fixture.date(0))

        let result = try await fixture.makeEngine().claimDue(
            definitionID: definition.id,
            at: fixture.date(1_000)
        )

        guard case let .claimed(runID) = result else {
            return XCTFail("Expected pending work to be claimed")
        }
        let run = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertEqual(run.occurrenceAt, fixture.date(900))
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(1_200))
        XCTAssertEqual(try fixture.runCount(), 2)
    }

    func testStaleOneShotIsCompletedAsSkippedWithoutRunningPreflight() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(0)
        let definition = try fixture.insertDefinition(
            recurrence: .once(occurrence),
            nextOccurrenceAt: occurrence
        )
        var didRunPreflight = false
        let engine = fixture.makeEngine { _ in
            didRunPreflight = true
            return .invalid(reason: "Preflight should not run for stale work.")
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: occurrence.addingTimeInterval(ScheduledTaskRecurrenceCalculator.defaultCatchUpAge + 1)
        )

        guard case let .skipped(runID) = result else {
            return XCTFail("Expected the stale one-shot to be skipped")
        }
        let run = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertEqual(run.status, .skipped)
        XCTAssertEqual(run.finishedAt, occurrence.addingTimeInterval(ScheduledTaskRecurrenceCalculator.defaultCatchUpAge + 1))
        XCTAssertEqual(definition.state, .completed)
        XCTAssertNil(definition.nextOccurrenceAt)
        XCTAssertFalse(didRunPreflight)
    }

}

@MainActor
private extension ScheduledTaskSchedulerEngineTests {
    func makeUnavailablePinnedBaseValidator(
        expectedProjectPath: String
    ) -> DefaultScheduledTaskPreflightValidator {
        DefaultScheduledTaskPreflightValidator(
            loadProviderStatus: { _, _ in nil },
            canonicalizeRoots: { roots, primaryRoot in
                roots.map(CanonicalPath.normalize).filter { $0 != primaryRoot }
            },
            checkDirectoryAccess: { _, _ in true },
            loadDirectoryIdentity: { _ in
                TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 1)
            },
            checkWorktreeFeasibility: { projectPath, baseRef, remoteName, projectIdentity in
                XCTAssertEqual(projectPath, expectedProjectPath)
                XCTAssertEqual(baseRef, "release/missing")
                XCTAssertEqual(remoteName, "upstream")
                XCTAssertEqual(projectIdentity, TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 1))
                throw NSError(
                    domain: "ScheduledTaskSchedulerEngineTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Pinned base release/missing is unavailable."]
                )
            }
        )
    }
}

@MainActor
struct ScheduledTaskSchedulerFixture {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func makeEngine(
        preflight: @escaping ScheduledTaskPreflightValidator = { snapshot in
            scheduledTaskReadyOutcome(for: snapshot)
        },
        saveState: @escaping ScheduledTaskSchedulerEngine.StateSaver = { try $0.save() }
    ) -> ScheduledTaskSchedulerEngine {
        ScheduledTaskSchedulerEngine(
            modelContext: context,
            preflightValidator: preflight,
            saveState: saveState
        )
    }

    func insertDefinition(
        state: ScheduledTaskState = .active,
        recurrence: ScheduledTaskRecurrence = .daily(hour: 8, minute: 0),
        nextOccurrenceAt: Date?,
        pendingOccurrenceAt: Date? = nil,
        project: Project? = nil,
        grantedRoots: [String] = []
    ) throws -> ScheduledTask {
        let definition = ScheduledTask(
            title: "Scheduled work",
            prompt: "Perform the work.",
            state: state,
            recurrence: recurrence,
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            model: "gpt-5",
            effort: "high",
            permissionMode: "acceptEdits",
            workspaceKind: project == nil ? .privateWorkspace : .project,
            workspaceStrategy: .worktree,
            grantedRoots: grantedRoots,
            project: project,
            nextOccurrenceAt: nextOccurrenceAt,
            pendingOccurrenceAt: pendingOccurrenceAt
        )
        context.insert(definition)
        try context.save()
        return definition
    }

    @discardableResult
    func insertRun(
        definition: ScheduledTask,
        status: ScheduledTaskRunStatus,
        occurrenceAt: Date
    ) throws -> ScheduledTaskRun {
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: UUID().uuidString,
            occurrenceAt: occurrenceAt,
            triggerKind: .scheduled,
            status: status
        )
        context.insert(run)
        try context.save()
        return run
    }

    func runCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<ScheduledTaskRun>())
    }

    func run(id: PersistentIdentifier) -> ScheduledTaskRun? {
        context.resolveScheduledTaskRun(id: id)
    }

    func date(_ timeInterval: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timeInterval)
    }
}

func scheduledTaskReadyOutcome(
    for snapshot: ScheduledTaskPreflightSnapshot
) -> ScheduledTaskPreflightOutcome {
    .ready(scheduledTaskTestWorkspaceIdentities(for: snapshot))
}

func scheduledTaskTestWorkspaceIdentities(
    for snapshot: ScheduledTaskPreflightSnapshot
) -> ScheduledTaskWorkspaceIdentitySnapshot {
    let projectRoot = snapshot.workspaceKind == .project ? snapshot.projectPath.map { path in
        ScheduledTaskRootIdentitySnapshot(
            path: path,
            identity: TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 1)
        )
    } : nil
    let grantedRoots = snapshot.grantedRoots.enumerated().map { index, path in
        ScheduledTaskRootIdentitySnapshot(
            path: path,
            identity: TaskWorkspaceFileSystemIdentity(
                systemNumber: 1,
                fileNumber: UInt64(index + 2)
            )
        )
    }
    return ScheduledTaskWorkspaceIdentitySnapshot(
        projectRoot: projectRoot,
        grantedRoots: grantedRoots
    )
}
