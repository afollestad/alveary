import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationViewAsyncRoutingTests: XCTestCase {
    func testHarnessDiscoveryUsesSavedSourceForBothWorkspaceModes() {
        let project = Project(path: "/tmp/source-project", name: "Source")
        let projectThread = AgentThread(
            name: "Project worktree",
            worktreePath: "/tmp/project-worktree",
            project: project
        )
        let taskThread = AgentThread(
            name: "Task worktree",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/task-worktree",
                ownershipStrategy: .projectWorktreeOwned,
                ownershipMarkerID: UUID().uuidString.lowercased(),
                sourceProjectPath: project.path
            )
        )

        XCTAssertEqual(
            ConversationView.harnessDiscoveryURL(for: projectThread)?.path,
            CanonicalPath.normalize(project.path)
        )
        XCTAssertEqual(
            ConversationView.harnessDiscoveryURL(for: taskThread)?.path,
            CanonicalPath.normalize(project.path)
        )
    }

    func testStaleHarnessDiscoveryCannotOverwriteOrCacheUnderNewProject() async {
        ComposerHarnessStatusCache.removeAll()
        defer { ComposerHarnessStatusCache.removeAll() }

        let projectAURL = URL(fileURLWithPath: "/tmp/project-a", isDirectory: true)
        let projectBURL = URL(fileURLWithPath: "/tmp/project-b", isDirectory: true)
        let requestA = ConversationAsyncRouting.HarnessStatusRequest(key: "request-a", projectURL: projectAURL)
        let requestB = ConversationAsyncRouting.HarnessStatusRequest(key: "request-b", projectURL: projectBURL)
        let harnessDiscovery = PausingHarnessDiscovery(responses: [
            projectAURL.path: [.claude: harnessStatus(for: .claude)],
            projectBURL.path: [.codex: harnessStatus(for: .codex)]
        ])
        let state = ConversationAsyncRoutingTestState()
        state.currentHarnessRequestKey = requestA.key

        let taskA = Task { @MainActor in
            await ConversationAsyncRouting.loadHarnessStatuses(
                request: requestA,
                harnessDiscovery: harnessDiscovery,
                currentRequestKey: { state.currentHarnessRequestKey }
            )
        }
        await harnessDiscovery.waitUntilHarnessStatusesRequested(for: projectAURL.path)

        state.currentHarnessRequestKey = requestB.key
        let taskB = Task { @MainActor in
            await ConversationAsyncRouting.loadHarnessStatuses(
                request: requestB,
                harnessDiscovery: harnessDiscovery,
                currentRequestKey: { state.currentHarnessRequestKey }
            )
        }
        await harnessDiscovery.waitUntilHarnessStatusesRequested(for: projectBURL.path)

        await harnessDiscovery.resumeHarnessStatuses(for: projectBURL.path)
        let resultB = await taskB.value
        if let resultB {
            ConversationAsyncRouting.applyHarnessStatusResult(resultB) { state.appliedHarnessSnapshot = $0 }
        }

        await harnessDiscovery.resumeHarnessStatuses(for: projectAURL.path)
        let resultA = await taskA.value

        XCTAssertNil(resultA)
        XCTAssertEqual(resultB?.requestKey, requestB.key)
        XCTAssertEqual(Set(state.appliedHarnessSnapshot?.statuses.keys.map(\.self) ?? []), Set([.codex]))
        XCTAssertNil(ComposerHarnessStatusCache.snapshot(for: requestA.key))
        XCTAssertEqual(
            Set(ComposerHarnessStatusCache.snapshot(for: requestB.key)?.statuses.keys.map(\.self) ?? []),
            Set([.codex])
        )
    }

    /// A refresh keeps showing the last resolved snapshot for its key, so a new thread's model
    /// list and Goal-mode tooltip do not blank out while its own probe runs.
    func testARefreshReSeedsFromTheCachedSnapshotForItsOwnKey() {
        ComposerHarnessStatusCache.removeAll()
        defer { ComposerHarnessStatusCache.removeAll() }

        let request = ConversationAsyncRouting.HarnessStatusRequest(
            key: "request-a",
            projectURL: URL(fileURLWithPath: "/tmp/project-a", isDirectory: true)
        )
        let stored = ComposerHarnessStatusSnapshot(
            ordering: [.codex, .claude],
            statuses: [.claude: harnessStatus(for: .claude)]
        )
        ComposerHarnessStatusCache.store(stored, for: request.key)

        let seeded = ConversationAsyncRouting.seededHarnessStatusSnapshot(for: request)

        XCTAssertEqual(seeded?.ordering, [.codex, .claude])
        XCTAssertEqual(Set(seeded?.statuses.keys.map(\.self) ?? []), Set([.claude]))
    }

    /// A draft project reassignment changes the key, and the previous project's snapshot is not
    /// an honest answer for the new one — the composer must report not-loaded instead.
    func testARefreshUnderAnUnseenKeyHasNoSnapshotToReSeedFrom() {
        ComposerHarnessStatusCache.removeAll()
        defer { ComposerHarnessStatusCache.removeAll() }

        ComposerHarnessStatusCache.store(
            ComposerHarnessStatusSnapshot(ordering: [.claude], statuses: [.claude: harnessStatus(for: .claude)]),
            for: "request-a"
        )
        let requestB = ConversationAsyncRouting.HarnessStatusRequest(
            key: "request-b",
            projectURL: URL(fileURLWithPath: "/tmp/project-b", isDirectory: true)
        )

        XCTAssertNil(ConversationAsyncRouting.seededHarnessStatusSnapshot(for: requestB))
    }

}

@MainActor
private extension ConversationViewAsyncRoutingTests {
    func harnessStatus(for harnessID: AgentCLIKit.AgentHarnessID) -> AgentCLIKit.AgentHarnessStatus {
        let definition = switch harnessID {
        case .claude:
            AgentCLIKit.ClaudeHarnessDefinition.definition
        case .codex:
            AgentCLIKit.CodexHarnessDefinition.definition
        }
        return AgentCLIKit.AgentHarnessStatus(
            harnessId: harnessID,
            definition: definition,
            installation: .installed,
            availability: AgentCLIKit.AgentHarnessAvailability(
                harnessId: harnessID,
                executablePath: "/usr/local/bin/\(harnessID.rawValue)"
            ),
            setup: .ready,
            modelOptions: AgentCLIKit.AgentDefaultModelOptions.harnessDefault(for: harnessID)
        )
    }
}

@MainActor
private final class ConversationAsyncRoutingTestState {
    var currentHarnessRequestKey = ""
    var appliedHarnessSnapshot: ComposerHarnessStatusSnapshot?
}

private actor PausingHarnessDiscovery: AgentCLIKit.AgentHarnessDiscoveryService {
    typealias Statuses = [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]

    private let responses: [String: Statuses]
    private var requestedPaths: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var responseContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(responses: [String: Statuses]) {
        self.responses = responses
    }

    func harnessStatuses(projectURL: URL?) async -> Statuses {
        let path = projectURL?.path ?? ""
        requestedPaths.insert(path)
        requestWaiters.removeValue(forKey: path)?.forEach { $0.resume() }
        await withCheckedContinuation { responseContinuations[path] = $0 }
        return responses[path] ?? [:]
    }

    func installedHarnessStatuses(projectURL: URL?) async -> Statuses {
        (responses[projectURL?.path ?? ""] ?? [:]).filter { $0.value.isInstalled }
    }

    func availableHarnessStatuses(projectURL: URL?) async -> Statuses {
        (responses[projectURL?.path ?? ""] ?? [:]).filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for harnessId: AgentCLIKit.AgentHarnessID) async -> [AgentCLIKit.AgentModelOption] {
        responses.values.lazy.compactMap { $0[harnessId] }.first?.modelOptions ?? []
    }

    func stableHarnessOrdering() async -> [AgentCLIKit.AgentHarnessID] {
        [.claude, .codex]
    }

    func waitUntilHarnessStatusesRequested(for path: String) async {
        guard !requestedPaths.contains(path) else {
            return
        }
        await withCheckedContinuation { requestWaiters[path, default: []].append($0) }
    }

    func resumeHarnessStatuses(for path: String) {
        responseContinuations.removeValue(forKey: path)?.resume()
    }
}
