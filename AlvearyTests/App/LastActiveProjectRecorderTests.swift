import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class LastActiveProjectRecorderTests: XCTestCase {
    func testPersistenceStartsOnlyAfterTheSuspensionGateOpens() async throws {
        let fixture = try LastActiveProjectFixture()
        let gate = LastActiveProjectGate()
        let recorder = fixture.makeRecorder(gate: gate)

        let job = recorder.record(for: .project(fixture.alpha))
        await Task.yield()

        XCTAssertTrue(fixture.resolvedOwners.isEmpty)
        XCTAssertTrue(fixture.persistedPaths.isEmpty)

        gate.open()
        await job?.value

        XCTAssertEqual(fixture.persistedPaths, [fixture.alpha.path])
    }

    func testRapidProjectSelectionsLeaveTheFinalProjectPersisted() async throws {
        let fixture = try LastActiveProjectFixture()
        let gate = LastActiveProjectGate()
        let recorder = fixture.makeRecorder(gate: gate)

        let first = recorder.record(for: .project(fixture.alpha))
        let second = recorder.record(for: .project(fixture.beta))
        let third = recorder.record(for: .project(fixture.gamma))
        gate.open()
        await first?.value
        await second?.value
        await third?.value

        XCTAssertEqual(fixture.persistedPaths, [fixture.alpha.path, fixture.beta.path, fixture.gamma.path])
    }

    func testAStaleJobCannotOverwriteANewerProjectWrite() async throws {
        let fixture = try LastActiveProjectFixture()
        let gate = LastActiveProjectGate()
        let recorder = fixture.makeRecorder(gate: gate)

        let stale = recorder.record(for: .project(fixture.alpha))
        let newest = recorder.record(for: .project(fixture.beta))
        await gate.waitForWaiters(count: 2)

        // Finish the newer job first, then let the superseded one resume.
        gate.release(1)
        await newest?.value
        gate.release(0)
        await stale?.value

        XCTAssertEqual(fixture.persistedPaths, [fixture.beta.path])
    }

    func testGlobalSelectionsNeverScheduleAWrite() async throws {
        let fixture = try LastActiveProjectFixture()
        let recorder = fixture.makeRecorder(gate: LastActiveProjectGate(isOpen: true))

        XCTAssertNil(recorder.record(for: nil))
        XCTAssertNil(recorder.record(for: .skills))
        XCTAssertNil(recorder.record(for: .mcp))
        XCTAssertNil(recorder.record(for: .scheduled))
        XCTAssertNil(recorder.record(for: .settings))
        XCTAssertTrue(fixture.persistedPaths.isEmpty)
    }

    func testATaskSelectionDoesNotDiscardAPendingProjectWrite() async throws {
        let fixture = try LastActiveProjectFixture()
        let gate = LastActiveProjectGate()
        let recorder = fixture.makeRecorder(gate: gate)

        let projectJob = recorder.record(for: .project(fixture.alpha))
        let taskJob = recorder.record(for: .thread(fixture.task))
        gate.open()
        await projectJob?.value
        await taskJob?.value

        XCTAssertEqual(fixture.persistedPaths, [fixture.alpha.path])
    }

    func testAProjectThreadSelectionPersistsItsOwningProject() async throws {
        let fixture = try LastActiveProjectFixture()
        let recorder = fixture.makeRecorder(gate: LastActiveProjectGate(isOpen: true))

        await recorder.record(for: .thread(fixture.alphaThread))?.value

        XCTAssertEqual(fixture.persistedPaths, [fixture.alpha.path])
    }

    func testResolutionReadsLiveRowsThroughTheModelContext() throws {
        let fixture = try LastActiveProjectFixture()

        XCTAssertEqual(
            ContentView.resolveLastActiveProject(
                .project(fixture.alpha.persistentModelID),
                modelContext: fixture.context
            ),
            .path(fixture.alpha.path)
        )
        XCTAssertEqual(
            ContentView.resolveLastActiveProject(
                .thread(fixture.alphaThread.persistentModelID),
                modelContext: fixture.context
            ),
            .path(fixture.alpha.path)
        )
        XCTAssertEqual(
            ContentView.resolveLastActiveProject(
                .thread(fixture.task.persistentModelID),
                modelContext: fixture.context
            ),
            .unowned
        )
    }
}

@MainActor
private final class LastActiveProjectFixture {
    let container: ModelContainer
    let context: ModelContext
    let alpha: Project
    let beta: Project
    let gamma: Project
    let alphaThread: AgentThread
    let task: AgentThread
    private(set) var resolvedOwners: [LastActiveProjectOwner] = []
    private(set) var persistedPaths: [String?] = []

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
        alpha = Project(path: "/tmp/last-active-alpha", name: "Alpha")
        beta = Project(path: "/tmp/last-active-beta", name: "Beta")
        gamma = Project(path: "/tmp/last-active-gamma", name: "Gamma")
        alphaThread = AgentThread(name: "Alpha thread", project: alpha)
        alpha.threads.append(alphaThread)
        task = AgentThread(
            name: "Task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/last-active-task",
                ownershipStrategy: .projectLocal
            )
        )
        context.insert(alpha)
        context.insert(beta)
        context.insert(gamma)
        context.insert(task)
        try context.save()
    }

    func makeRecorder(gate: LastActiveProjectGate) -> LastActiveProjectRecorder {
        LastActiveProjectRecorder(
            resolve: { [weak self] owner in
                guard let self else {
                    return .unowned
                }
                resolvedOwners.append(owner)
                return ContentView.resolveLastActiveProject(owner, modelContext: context)
            },
            persist: { [weak self] path in
                self?.persistedPaths.append(path)
            },
            suspendBeforeResolving: { await gate.wait() }
        )
    }
}

@MainActor
private final class LastActiveProjectGate {
    private var isOpen: Bool
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var arrivalCount = 0

    init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    func open() {
        isOpen = true
        let pending = continuations.sorted { $0.key < $1.key }.map(\.value)
        continuations = [:]
        for continuation in pending {
            continuation.resume()
        }
    }

    /// Resumes one waiter by arrival index so job completion order can be controlled.
    func release(_ index: Int) {
        continuations.removeValue(forKey: index)?.resume()
    }

    func waitForWaiters(count: Int) async {
        while arrivalCount < count {
            await Task.yield()
        }
    }

    func wait() async {
        guard !isOpen else {
            return
        }
        let index = arrivalCount
        arrivalCount += 1
        await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
    }
}
