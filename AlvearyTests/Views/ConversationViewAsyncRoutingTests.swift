import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationViewAsyncRoutingTests: XCTestCase {
    func testProviderDiscoveryUsesProjectSourceButTaskPrimaryWorkspace() {
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
            CanonicalPath.normalize("/tmp/task-worktree")
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

    func testOlderWorkingDirectoryWarmCannotSwitchDiffAfterNewerReassignment() async throws {
        let fixture = try ConversationAsyncRoutingThreadFixture(threadCount: 1)
        let thread = try XCTUnwrap(fixture.threads.first)
        let fileListManager = PausingConversationFileListManager()
        let state = ConversationAsyncRoutingTestState()
        state.selectedSidebarItem = .thread(thread)
        state.currentWorkingDirectory = "/tmp/project-b"

        let taskB = diffSwitchTask(
            thread: thread,
            workingDirectory: "/tmp/project-b",
            fileListManager: fileListManager,
            state: state
        )
        await fileListManager.waitUntilWarmRequested(for: "/tmp/project-b")

        state.currentWorkingDirectory = "/tmp/project-c"
        let taskC = diffSwitchTask(
            thread: thread,
            workingDirectory: "/tmp/project-c",
            fileListManager: fileListManager,
            state: state
        )
        await fileListManager.waitUntilWarmRequested(for: "/tmp/project-c")

        await fileListManager.resumeWarm(for: "/tmp/project-c")
        await taskC.value
        await fileListManager.resumeWarm(for: "/tmp/project-b")
        await taskB.value

        XCTAssertEqual(state.switchedDirectories, ["/tmp/project-c"])
        withExtendedLifetime(fixture.container) {}
    }

    func testWorkingDirectoryWarmDoesNotSwitchDiffAfterThreadSelectionChanges() async throws {
        let fixture = try ConversationAsyncRoutingThreadFixture(threadCount: 2)
        let firstThread = try XCTUnwrap(fixture.threads.first)
        let secondThread = try XCTUnwrap(fixture.threads.last)
        let fileListManager = PausingConversationFileListManager()
        let state = ConversationAsyncRoutingTestState()
        state.selectedSidebarItem = .thread(firstThread)
        state.currentWorkingDirectory = "/tmp/shared-project"

        let task = diffSwitchTask(
            thread: firstThread,
            workingDirectory: "/tmp/shared-project",
            fileListManager: fileListManager,
            state: state
        )
        await fileListManager.waitUntilWarmRequested(for: "/tmp/shared-project")

        state.selectedSidebarItem = .thread(secondThread)
        await fileListManager.resumeWarm(for: "/tmp/shared-project")
        await task.value

        XCTAssertTrue(state.switchedDirectories.isEmpty)
        withExtendedLifetime(fixture.container) {}
    }

    func testDraftWorkingDirectoryWarmCannotClaimThreadScopedDiffTarget() async throws {
        let fixture = try ConversationAsyncRoutingThreadFixture(threadCount: 1)
        let thread = try XCTUnwrap(fixture.threads.first)
        thread.isDraft = true
        let fileListManager = PausingConversationFileListManager()
        let state = ConversationAsyncRoutingTestState()
        state.selectedSidebarItem = .thread(thread)
        state.currentWorkingDirectory = "/tmp/draft-project"

        let task = diffSwitchTask(
            thread: thread,
            workingDirectory: "/tmp/draft-project",
            allowsThreadScopedSwitch: !thread.isDraft,
            fileListManager: fileListManager,
            state: state
        )
        await fileListManager.waitUntilWarmRequested(for: "/tmp/draft-project")
        await fileListManager.resumeWarm(for: "/tmp/draft-project")
        await task.value

        XCTAssertTrue(state.switchedDirectories.isEmpty)
        withExtendedLifetime(fixture.container) {}
    }
}

@MainActor
private extension ConversationViewAsyncRoutingTests {
    func diffSwitchTask(
        thread: AgentThread,
        workingDirectory: String,
        allowsThreadScopedSwitch: Bool = true,
        fileListManager: FileListManager,
        state: ConversationAsyncRoutingTestState
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await ConversationAsyncRouting.warmFileCacheForDiffSwitch(
                request: .init(
                    threadID: thread.persistentModelID,
                    workingDirectory: workingDirectory,
                    allowsThreadScopedSwitch: allowsThreadScopedSwitch
                ),
                fileListManager: fileListManager,
                selectedSidebarItem: { state.selectedSidebarItem },
                currentWorkingDirectory: { state.currentWorkingDirectory },
                performSwitch: { state.switchedDirectories.append(workingDirectory) }
            )
        }
    }

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
    var selectedSidebarItem: SidebarItem?
    var currentWorkingDirectory: String?
    var switchedDirectories: [String] = []
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

private actor PausingConversationFileListManager: FileListManager {
    private var requestedPaths: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var warmContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    func files(for projectPath: String) async -> [String] {
        []
    }

    func invalidateCache(for projectPath: String) {}

    func warmCache(for projectPath: String) async {
        requestedPaths.insert(projectPath)
        requestWaiters.removeValue(forKey: projectPath)?.forEach { $0.resume() }
        await withCheckedContinuation { warmContinuations[projectPath] = $0 }
    }

    func waitUntilWarmRequested(for path: String) async {
        guard !requestedPaths.contains(path) else {
            return
        }
        await withCheckedContinuation { requestWaiters[path, default: []].append($0) }
    }

    func resumeWarm(for path: String) {
        warmContinuations.removeValue(forKey: path)?.resume()
    }
}

@MainActor
private struct ConversationAsyncRoutingThreadFixture {
    let container: ModelContainer
    let threads: [AgentThread]

    init(threadCount: Int) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/shared-project", name: "Shared")
        context.insert(project)
        threads = (0..<threadCount).map { index in
            let thread = AgentThread(name: "Thread \(index)", project: project)
            context.insert(thread)
            return thread
        }
        try context.save()
    }
}
