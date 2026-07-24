import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ContentViewDiffViewerRoutingTests: XCTestCase {
    func testSettingsNormalizesToItsPreservedBookmarkRoute() throws {
        let fixture = try DiffRoutingFixture()

        let projectSelection = DiffViewerRoutingSelection(
            selection: .project(fixture.project),
            previousSelection: nil
        )
        let settingsSelection = DiffViewerRoutingSelection(
            selection: .settings,
            previousSelection: .projectPath(fixture.project.path)
        )
        let threadSelection = DiffViewerRoutingSelection(
            selection: .thread(fixture.thread),
            previousSelection: nil
        )
        let settingsThreadSelection = DiffViewerRoutingSelection(
            selection: .settings,
            previousSelection: .threadId(fixture.thread.persistentModelID)
        )

        XCTAssertEqual(projectSelection, settingsSelection)
        XCTAssertEqual(threadSelection, settingsThreadSelection)
    }

    func testNonRoutableSelectionsResolveToNoRoute() throws {
        XCTAssertEqual(DiffViewerRoutingSelection(selection: nil, previousSelection: nil), .none)
        XCTAssertEqual(DiffViewerRoutingSelection(selection: .skills, previousSelection: nil), .none)
        XCTAssertEqual(DiffViewerRoutingSelection(selection: .mcp, previousSelection: nil), .none)
        XCTAssertEqual(
            DiffViewerRoutingSelection(selection: .settings, previousSelection: .scheduled),
            .none
        )
    }

    func testProjectScopedConversationFetchMatchesTheNestedRelationship() throws {
        let fixture = try DiffRoutingFixture()
        let otherProject = Project(path: "/tmp/diff-routing-other", name: "Other")
        let otherThread = AgentThread(name: "Other thread", project: otherProject)
        otherProject.threads.append(otherThread)
        otherThread.conversations = [Conversation(id: "other", title: "Other", provider: "claude", thread: otherThread)]
        fixture.thread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", thread: fixture.thread)
        ]
        fixture.context.insert(otherProject)
        try fixture.context.save()

        // Locks in the two-level predicate the batched project fetch depends on.
        let projectPath = fixture.project.path
        let conversations = try fixture.context.fetch(
            FetchDescriptor<Conversation>(
                predicate: #Predicate { conversation in
                    conversation.thread?.project?.path == projectPath
                }
            )
        )

        XCTAssertEqual(conversations.map(\.id), ["main"])
    }

    func testResolutionAndPaneWorkStartOnlyAfterTheSuspensionGate() async throws {
        let recorder = DiffRoutingRecorder()
        let gate = DiffRoutingGate()
        let key = DiffViewerRoutingKey(selection: .project("/tmp/a"), scope: .full, draftRevision: 0)
        let runner = recorder.makeRunner(currentKey: key, gate: gate)

        let routing = Task { await runner.run(key: key) }
        await Task.yield()

        XCTAssertTrue(recorder.resolvedSelections.isEmpty)
        XCTAssertTrue(recorder.appliedTargets.isEmpty)

        gate.open()
        await routing.value

        XCTAssertEqual(recorder.resolvedSelections, [.project("/tmp/a")])
        XCTAssertEqual(recorder.appliedTargets.map(\.scope), [.full])
        XCTAssertEqual(recorder.clearCount, 0)
    }

    func testOnlyTheNewestKeyOfARapidSelectionBurstIsApplied() async {
        let recorder = DiffRoutingRecorder()
        let gate = DiffRoutingGate()
        let currentKey = DiffViewerRoutingKey(selection: .project("/tmp/c"), scope: .full, draftRevision: 0)
        let stale = DiffViewerRoutingKey(selection: .project("/tmp/a"), scope: .full, draftRevision: 0)
        let superseded = DiffViewerRoutingKey(selection: .project("/tmp/b"), scope: .full, draftRevision: 0)
        let runner = recorder.makeRunner(currentKey: { currentKey }, gate: gate)

        let routing = Task {
            await runner.run(key: stale)
            await runner.run(key: superseded)
            await runner.run(key: currentKey)
        }
        gate.open()
        await routing.value

        XCTAssertEqual(recorder.resolvedSelections, [.project("/tmp/c")])
        XCTAssertEqual(recorder.appliedTargets.map(\.target.projectPath), ["/tmp/c"])
    }

    func testAStaleRouteThatLosesItsTargetDoesNotClearTheNewerPane() async {
        let recorder = DiffRoutingRecorder()
        recorder.target = nil
        let gate = DiffRoutingGate(isOpen: true)
        let current = DiffViewerRoutingKey(selection: .project("/tmp/current"), scope: .full, draftRevision: 0)
        let stale = DiffViewerRoutingKey(selection: .none, scope: .full, draftRevision: 0)
        let runner = recorder.makeRunner(currentKey: current, gate: gate)

        await runner.run(key: stale)

        XCTAssertEqual(recorder.clearCount, 0)
        XCTAssertTrue(recorder.appliedTargets.isEmpty)
    }

    func testAnEmptyCurrentRouteClearsThePane() async {
        let recorder = DiffRoutingRecorder()
        recorder.target = nil
        let gate = DiffRoutingGate(isOpen: true)
        let key = DiffViewerRoutingKey(selection: .none, scope: .toolbarStatsOnly, draftRevision: 0)
        let runner = recorder.makeRunner(currentKey: key, gate: gate)

        await runner.run(key: key)

        XCTAssertEqual(recorder.clearCount, 1)
        XCTAssertTrue(recorder.appliedTargets.isEmpty)
    }

    func testHiddenPaneRoutesStatsOnlyAndVisiblePaneRoutesFull() async {
        let recorder = DiffRoutingRecorder()
        let gate = DiffRoutingGate(isOpen: true)
        let hidden = DiffViewerRoutingKey(
            selection: .project("/tmp/scope"),
            scope: .toolbarStatsOnly,
            draftRevision: 0
        )
        let visible = DiffViewerRoutingKey(selection: .project("/tmp/scope"), scope: .full, draftRevision: 0)
        var currentKey = hidden
        let runner = recorder.makeRunner(currentKey: { currentKey }, gate: gate)

        await runner.run(key: hidden)
        currentKey = visible
        await runner.run(key: visible)

        XCTAssertEqual(recorder.appliedTargets.map(\.scope), [.toolbarStatsOnly, .full])
    }

    func testKeyDistinguishesScopeAndDraftRevisionForTheSameSelection() {
        let base = DiffViewerRoutingKey(selection: .project("/tmp/key"), scope: .full, draftRevision: 0)

        XCTAssertEqual(base, DiffViewerRoutingKey(selection: .project("/tmp/key"), scope: .full, draftRevision: 0))
        XCTAssertNotEqual(
            base,
            DiffViewerRoutingKey(selection: .project("/tmp/key"), scope: .toolbarStatsOnly, draftRevision: 0)
        )
        XCTAssertNotEqual(
            base,
            DiffViewerRoutingKey(selection: .project("/tmp/key"), scope: .full, draftRevision: 1)
        )
    }
}

@MainActor
private final class DiffRoutingRecorder {
    var target: DiffViewerSwitchTarget? = DiffViewerSwitchTarget(
        projectPath: "/tmp/placeholder",
        worktreePath: nil,
        directory: "/tmp/placeholder",
        baseRef: "main",
        remoteName: nil,
        conversationIds: []
    )
    private(set) var resolvedSelections: [DiffViewerRoutingSelection] = []
    private(set) var appliedTargets: [(target: DiffViewerSwitchTarget, scope: DiffViewerSwitchScope)] = []
    private(set) var clearCount = 0

    func makeRunner(currentKey: DiffViewerRoutingKey, gate: DiffRoutingGate) -> DiffViewerRouteRunner {
        makeRunner(currentKey: { currentKey }, gate: gate)
    }

    func makeRunner(
        currentKey: @escaping @MainActor () -> DiffViewerRoutingKey,
        gate: DiffRoutingGate
    ) -> DiffViewerRouteRunner {
        DiffViewerRouteRunner(
            isCurrent: { key in key == currentKey() },
            resolveTarget: { [weak self] selection in
                guard let self else {
                    return nil
                }
                resolvedSelections.append(selection)
                guard case .project(let path) = selection else {
                    return target
                }
                return target.map {
                    DiffViewerSwitchTarget(
                        projectPath: path,
                        worktreePath: $0.worktreePath,
                        directory: path,
                        baseRef: $0.baseRef,
                        remoteName: $0.remoteName,
                        conversationIds: $0.conversationIds
                    )
                }
            },
            clear: { [weak self] in self?.clearCount += 1 },
            applyTarget: { [weak self] target, scope in
                self?.appliedTargets.append((target, scope))
            },
            suspendBeforeResolving: { await gate.wait() }
        )
    }
}

@MainActor
private final class DiffRoutingGate {
    private var isOpen: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume()
        }
    }

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

@MainActor
private struct DiffRoutingFixture {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread

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
        project = Project(path: "/tmp/diff-routing-project", name: "Routing")
        thread = AgentThread(name: "Routing thread", project: project)
        project.threads.append(thread)
        context.insert(project)
        try context.save()
    }
}
