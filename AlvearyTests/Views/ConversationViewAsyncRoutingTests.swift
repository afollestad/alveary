import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationViewAsyncRoutingTests: XCTestCase {
    func testProviderDiscoveryUsesSavedSourceForBothWorkspaceModes() {
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
            ConversationView.providerDiscoveryURL(for: projectThread)?.path,
            CanonicalPath.normalize(project.path)
        )
        XCTAssertEqual(
            ConversationView.providerDiscoveryURL(for: taskThread)?.path,
            CanonicalPath.normalize(project.path)
        )
    }

    func testStaleProviderDiscoveryCannotOverwriteOrCacheUnderNewProject() async {
        ComposerProviderStatusCache.removeAll()
        defer { ComposerProviderStatusCache.removeAll() }

        let projectAURL = URL(fileURLWithPath: "/tmp/project-a", isDirectory: true)
        let projectBURL = URL(fileURLWithPath: "/tmp/project-b", isDirectory: true)
        let requestA = ConversationAsyncRouting.ProviderStatusRequest(key: "request-a", projectURL: projectAURL)
        let requestB = ConversationAsyncRouting.ProviderStatusRequest(key: "request-b", projectURL: projectBURL)
        let providerDiscovery = PausingProviderDiscovery(responses: [
            projectAURL.path: [.claude: providerStatus(for: .claude)],
            projectBURL.path: [.codex: providerStatus(for: .codex)]
        ])
        let state = ConversationAsyncRoutingTestState()
        state.currentProviderRequestKey = requestA.key

        let taskA = Task { @MainActor in
            await ConversationAsyncRouting.loadProviderStatuses(
                request: requestA,
                providerDiscovery: providerDiscovery,
                currentRequestKey: { state.currentProviderRequestKey }
            )
        }
        await providerDiscovery.waitUntilProviderStatusesRequested(for: projectAURL.path)

        state.currentProviderRequestKey = requestB.key
        let taskB = Task { @MainActor in
            await ConversationAsyncRouting.loadProviderStatuses(
                request: requestB,
                providerDiscovery: providerDiscovery,
                currentRequestKey: { state.currentProviderRequestKey }
            )
        }
        await providerDiscovery.waitUntilProviderStatusesRequested(for: projectBURL.path)

        await providerDiscovery.resumeProviderStatuses(for: projectBURL.path)
        let resultB = await taskB.value
        if let resultB {
            ConversationAsyncRouting.applyProviderStatusResult(resultB) { state.appliedProviderSnapshot = $0 }
        }

        await providerDiscovery.resumeProviderStatuses(for: projectAURL.path)
        let resultA = await taskA.value

        XCTAssertNil(resultA)
        XCTAssertEqual(resultB?.requestKey, requestB.key)
        XCTAssertEqual(Set(state.appliedProviderSnapshot?.statuses.keys.map(\.self) ?? []), Set([.codex]))
        XCTAssertNil(ComposerProviderStatusCache.snapshot(for: requestA.key))
        XCTAssertEqual(
            Set(ComposerProviderStatusCache.snapshot(for: requestB.key)?.statuses.keys.map(\.self) ?? []),
            Set([.codex])
        )
    }

    /// A refresh keeps showing the last resolved snapshot for its key, so a new thread's model
    /// list and Goal-mode tooltip do not blank out while its own probe runs.
    func testARefreshReSeedsFromTheCachedSnapshotForItsOwnKey() {
        ComposerProviderStatusCache.removeAll()
        defer { ComposerProviderStatusCache.removeAll() }

        let request = ConversationAsyncRouting.ProviderStatusRequest(
            key: "request-a",
            projectURL: URL(fileURLWithPath: "/tmp/project-a", isDirectory: true)
        )
        let stored = ComposerProviderStatusSnapshot(
            ordering: [.codex, .claude],
            statuses: [.claude: providerStatus(for: .claude)]
        )
        ComposerProviderStatusCache.store(stored, for: request.key)

        let seeded = ConversationAsyncRouting.seededProviderStatusSnapshot(for: request)

        XCTAssertEqual(seeded?.ordering, [.codex, .claude])
        XCTAssertEqual(Set(seeded?.statuses.keys.map(\.self) ?? []), Set([.claude]))
    }

    /// A draft project reassignment changes the key, and the previous project's snapshot is not
    /// an honest answer for the new one — the composer must report not-loaded instead.
    func testARefreshUnderAnUnseenKeyHasNoSnapshotToReSeedFrom() {
        ComposerProviderStatusCache.removeAll()
        defer { ComposerProviderStatusCache.removeAll() }

        ComposerProviderStatusCache.store(
            ComposerProviderStatusSnapshot(ordering: [.claude], statuses: [.claude: providerStatus(for: .claude)]),
            for: "request-a"
        )
        let requestB = ConversationAsyncRouting.ProviderStatusRequest(
            key: "request-b",
            projectURL: URL(fileURLWithPath: "/tmp/project-b", isDirectory: true)
        )

        XCTAssertNil(ConversationAsyncRouting.seededProviderStatusSnapshot(for: requestB))
    }

}

@MainActor
private extension ConversationViewAsyncRoutingTests {
    func providerStatus(for providerID: AgentCLIKit.AgentProviderID) -> AgentCLIKit.AgentProviderStatus {
        let definition = switch providerID {
        case .claude:
            AgentCLIKit.ClaudeProviderDefinition.definition
        case .codex:
            AgentCLIKit.CodexProviderDefinition.definition
        }
        return AgentCLIKit.AgentProviderStatus(
            providerId: providerID,
            definition: definition,
            installation: .installed,
            availability: AgentCLIKit.AgentProviderAvailability(
                providerId: providerID,
                executablePath: "/usr/local/bin/\(providerID.rawValue)"
            ),
            setup: .ready,
            modelOptions: AgentCLIKit.AgentDefaultModelOptions.providerDefault(for: providerID)
        )
    }
}

@MainActor
private final class ConversationAsyncRoutingTestState {
    var currentProviderRequestKey = ""
    var appliedProviderSnapshot: ComposerProviderStatusSnapshot?
}

private actor PausingProviderDiscovery: AgentCLIKit.AgentProviderDiscoveryService {
    typealias Statuses = [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]

    private let responses: [String: Statuses]
    private var requestedPaths: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var responseContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(responses: [String: Statuses]) {
        self.responses = responses
    }

    func providerStatuses(projectURL: URL?) async -> Statuses {
        let path = projectURL?.path ?? ""
        requestedPaths.insert(path)
        requestWaiters.removeValue(forKey: path)?.forEach { $0.resume() }
        await withCheckedContinuation { responseContinuations[path] = $0 }
        return responses[path] ?? [:]
    }

    func installedProviderStatuses(projectURL: URL?) async -> Statuses {
        (responses[projectURL?.path ?? ""] ?? [:]).filter { $0.value.isInstalled }
    }

    func availableProviderStatuses(projectURL: URL?) async -> Statuses {
        (responses[projectURL?.path ?? ""] ?? [:]).filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        responses.values.lazy.compactMap { $0[providerId] }.first?.modelOptions ?? []
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }

    func waitUntilProviderStatusesRequested(for path: String) async {
        guard !requestedPaths.contains(path) else {
            return
        }
        await withCheckedContinuation { requestWaiters[path, default: []].append($0) }
    }

    func resumeProviderStatuses(for path: String) {
        responseContinuations.removeValue(forKey: path)?.resume()
    }
}
