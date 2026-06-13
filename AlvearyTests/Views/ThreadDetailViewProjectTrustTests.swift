import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadDetailViewProjectTrustTests: XCTestCase {
    func testDenyProjectTrustRoutesThroughInjectedThreadDelete() async throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        await fixture.view.denyProjectTrust(fixture.prompt)

        let deletedThreadIDs = fixture.deleteRecorder.deletedThreadIDs
        XCTAssertEqual(deletedThreadIDs, [fixture.thread.persistentModelID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(fixture.project))
        XCTAssertNil(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID])
    }

    func testDenyProjectTrustDoesNotRollbackSelectionForPostCommitCleanupFailure() async throws {
        let fixture = try ThreadDetailProjectTrustFixture(deleteError: SidebarViewModelError.threadDeleteCleanupFailed(
            ThreadDetailProjectTrustError.cleanupFailed
        ))

        await fixture.view.denyProjectTrust(fixture.prompt)

        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(fixture.project))
        XCTAssertNil(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID])
        XCTAssertEqual(
            fixture.appState.unexpectedErrorToasts.map(\.message),
            ["Thread was deleted, but cleanup failed: Cleanup failed"]
        )
    }

    func testDenyProjectTrustRollsBackSelectionForPreCommitDeleteFailure() async throws {
        let fixture = try ThreadDetailProjectTrustFixture(
            deleteError: ThreadDetailProjectTrustError.cleanupFailed,
            deletesBeforeThrowing: false
        )

        await fixture.view.denyProjectTrust(fixture.prompt)

        XCTAssertEqual(fixture.appState.selectedSidebarItem, .thread(fixture.thread))
        XCTAssertEqual(fixture.appState.previousSelection, .threadId(fixture.thread.persistentModelID))
        XCTAssertEqual(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID], fixture.conversation.persistentModelID)
        XCTAssertEqual(fixture.deleteRecorder.deletedThreadIDs, [fixture.thread.persistentModelID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
    }
}

@MainActor
private struct ThreadDetailProjectTrustFixture {
    let container: ModelContainer
    let context: ModelContext
    let appState: AppState
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
    let prompt: ProjectTrustPrompt
    let deleteRecorder: ThreadDetailDeleteRecorder
    let view: ThreadDetailView

    init(deleteError: Error? = nil, deletesBeforeThrowing: Bool = true) throws {
        let seededModel = try Self.makeSeededModel()
        container = seededModel.container
        context = seededModel.context
        project = seededModel.project
        thread = seededModel.thread
        conversation = seededModel.conversation
        appState = Self.makeAppState(thread: thread, conversation: conversation)
        prompt = ProjectTrustPrompt(
            threadID: thread.persistentModelID,
            canonicalProjectPath: "/tmp/alveary-project",
            projectName: "Alveary",
            providerID: "claude"
        )
        let recorder = ThreadDetailDeleteRecorder(
            context: context,
            deleteError: deleteError,
            deletesBeforeThrowing: deletesBeforeThrowing
        )
        deleteRecorder = recorder

        view = Self.makeView(
            thread: thread,
            appState: appState,
            context: context,
            recorder: recorder
        )
    }

    private static func makeSeededModel() throws -> SeededModel {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Needs Trust", hasCompletedInitialSetup: false, project: project)
        let conversation = Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: thread)
        thread.conversations = [conversation]
        project.threads = [thread]
        context.insert(project)
        try context.save()
        return SeededModel(container: container, context: context, project: project, thread: thread, conversation: conversation)
    }

    private static func makeAppState(thread: AgentThread, conversation: Conversation) -> AppState {
        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)
        appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        return appState
    }

    private static func makeView(
        thread: AgentThread,
        appState: AppState,
        context: ModelContext,
        recorder: ThreadDetailDeleteRecorder
    ) -> ThreadDetailView {
        let fileListManager = SnapshotMockFileListManager()
        return ThreadDetailView(
            thread: thread,
            appState: appState,
            modelContext: context,
            agentsManager: SidebarMockAgentsManager(),
            runtimeStore: MockConversationRuntimeStore(),
            keepAwakeService: RecordingKeepAwakeService(),
            settingsService: InMemorySettingsService(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            providerDiscovery: SnapshotThreadProviderDiscoveryService(),
            worktreeManager: MockWorktreeManager(worktreeInfo: WorktreeInfo(path: "/tmp/alveary-worktree", branch: "main")),
            providerSetup: MockProviderSetupService(),
            contextWindowCache: MockContextWindowCache(),
            fileListManager: fileListManager,
            notificationManager: RecordingNotificationManager(),
            threadActivityRecorder: NoopThreadActivityRecorder(),
            deleteThread: { thread in
                try await recorder.delete(thread)
            },
            loadSkillCompletions: { [] },
            diffViewModel: DiffViewerViewModel(
                gitService: SnapshotMockGitService(statusResults: [[]], diffResults: [""]),
                gitHubService: SnapshotMockGitHubService(),
                fileListManager: fileListManager,
                agentsManager: SidebarMockAgentsManager(),
                fsEventDebounceDuration: .seconds(10),
                idlePollInterval: .seconds(10)
            )
        )
    }
}

private struct SeededModel {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
}

@MainActor
private final class ThreadDetailDeleteRecorder {
    private let context: ModelContext
    private let deleteError: Error?
    private let deletesBeforeThrowing: Bool
    private(set) var deletedThreadIDs: [PersistentIdentifier] = []

    init(context: ModelContext, deleteError: Error?, deletesBeforeThrowing: Bool) {
        self.context = context
        self.deleteError = deleteError
        self.deletesBeforeThrowing = deletesBeforeThrowing
    }

    func delete(_ thread: AgentThread) async throws {
        deletedThreadIDs.append(thread.persistentModelID)
        if let deleteError, !deletesBeforeThrowing {
            throw deleteError
        }
        if let dbThread = context.resolveThread(id: thread.persistentModelID) {
            context.delete(dbThread)
            try context.save()
        }
        if let deleteError {
            throw deleteError
        }
    }
}

private enum ThreadDetailProjectTrustError: LocalizedError {
    case cleanupFailed

    var errorDescription: String? {
        "Cleanup failed"
    }
}
