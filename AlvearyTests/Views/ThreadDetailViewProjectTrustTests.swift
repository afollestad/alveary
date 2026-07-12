import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class ThreadDetailViewProjectTrustTests: XCTestCase {
    func testUninitializedThreadHidesConversationStrip() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        XCTAssertFalse(fixture.view.shouldShowConversationStrip)
    }

    func testUninitializedThreadEmptyStateDoesNotOfferInertCreateAction() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        XCTAssertFalse(fixture.view.canCreateConversationFromEmptyState)
    }

    func testInitializedRealThreadEmptyStateOffersCreateAction() throws {
        let fixture = try ThreadDetailProjectTrustFixture(hasCompletedInitialSetup: true)

        XCTAssertTrue(fixture.view.canCreateConversationFromEmptyState)
    }

    func testDraftEmptyConversationStateDoesNotPersistRestoreSelection() throws {
        let fixture = try ThreadDetailProjectTrustFixture(isDraft: true)

        XCTAssertFalse(fixture.view.canPersistEmptyConversationSelection)
    }

    func testHostedCloseShortcutWithStripAbsentConsumesSingleConversationWithoutRemovingOrClosingWindow() throws {
        let fixture = try ThreadDetailProjectTrustFixture()
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: [fixture.conversation],
            selectedConversation: fixture.conversation,
            isRenaming: false
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    func testHostedCloseShortcutWithStripAbsentConsumesRenameWithoutRemovingOrClosingWindow() throws {
        let fixture = try ThreadDetailProjectTrustFixture()
        let sideConversation = Conversation(
            id: "side",
            title: "Side",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: [fixture.conversation, sideConversation],
            selectedConversation: sideConversation,
            isRenaming: true
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    func testHostedCloseShortcutWithStripAbsentRemovesSelectedConversationWhenMultipleExist() throws {
        let fixture = try ThreadDetailProjectTrustFixture()
        let sideConversation = Conversation(
            id: "side",
            title: "Side",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: [fixture.conversation, sideConversation],
            selectedConversation: sideConversation,
            isRenaming: false
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertEqual(removedConversationIDs, [sideConversation.persistentModelID])
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    func testTransientEmptyConversationFetchPreservesSelectedConversation() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        let resolved = ThreadDetailConversationResolver.resolve(
            fetchedConversations: [],
            thread: fixture.thread,
            selectedConversationID: fixture.conversation.persistentModelID,
            modelContext: fixture.context
        )

        XCTAssertEqual(resolved.map(\.persistentModelID), [fixture.conversation.persistentModelID])
    }

    func testTransientEmptyConversationFetchFallsBackToSecondaryFetch() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        let resolved = ThreadDetailConversationResolver.resolve(
            fetchedConversations: nil,
            thread: fixture.thread,
            selectedConversationID: nil,
            modelContext: fixture.context
        )

        XCTAssertEqual(resolved.map(\.persistentModelID), [fixture.conversation.persistentModelID])
    }

    func testStaleTrustCheckCannotAutoTrustPreviousDraftProjectAfterReassignment() async throws {
        let originalPath = "/tmp/alveary-project"
        let replacementPath = "/tmp/reassigned-project"
        let providerSetup = PausingThreadDetailProjectTrustService(pausedProjectPath: originalPath)
        var settings = AppSettings()
        settings.autoTrustProjects = true
        let fixture = try ThreadDetailProjectTrustFixture(
            isDraft: true,
            settings: settings,
            providerSetup: providerSetup
        )

        let originalRefresh = Task { @MainActor in
            await fixture.view.refreshProjectTrustPrompt(for: fixture.conversation)
        }
        await providerSetup.waitUntilStatusPaused()

        let replacementProject = Project(path: replacementPath, name: "Reassigned")
        fixture.context.insert(replacementProject)
        fixture.thread.project = replacementProject
        try fixture.context.save()

        await fixture.view.refreshProjectTrustPrompt(for: fixture.conversation)
        await providerSetup.resumePausedStatus()
        await originalRefresh.value

        let trustedProjectPaths = await providerSetup.recordedTrustedProjectPaths()
        XCTAssertEqual(trustedProjectPaths, [CanonicalPath.normalize(replacementPath)])
        XCTAssertNil(fixture.view.projectTrustPrompt)
        XCTAssertFalse(fixture.view.isCheckingProjectTrust)
    }

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
private final class HostedConversationCloseShortcut {
    private let controller: NSHostingController<AnyView>
    private let closeRecorder: ConversationCloseWindowDelegate
    private let window: NSWindow

    var closeRequestCount: Int { closeRecorder.closeRequestCount }
    var isWindowVisible: Bool { window.isVisible }

    init(
        conversations: [Conversation],
        selectedConversation: Conversation?,
        isRenaming: Bool,
        onRemove: @escaping (Conversation) -> Void
    ) {
        let rootView = ConversationCloseShortcutSink(
            conversations: conversations,
            selectedConversation: selectedConversation,
            isRenaming: isRenaming,
            onRemove: onRemove
        )
        .frame(width: 320, height: 180)
        controller = NSHostingController(rootView: AnyView(rootView))
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 180)

        let window = NSWindow(
            contentRect: NSRect(x: -1320, y: -1180, width: 320, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let closeRecorder = ConversationCloseWindowDelegate()
        self.closeRecorder = closeRecorder
        self.window = window
        window.delegate = closeRecorder
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.view)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
    }

    func performCommandW() throws -> Bool {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))
        return window.performKeyEquivalent(with: event)
    }

    func close() {
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }
}

private final class ConversationCloseWindowDelegate: NSObject, NSWindowDelegate {
    private(set) var closeRequestCount = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequestCount += 1
        return true
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

    init(
        deleteError: Error? = nil,
        deletesBeforeThrowing: Bool = true,
        isDraft: Bool = false,
        hasCompletedInitialSetup: Bool = false,
        settings: AppSettings = AppSettings(),
        providerSetup: (any ProviderSetupService)? = nil
    ) throws {
        let seededModel = try Self.makeSeededModel(
            isDraft: isDraft,
            hasCompletedInitialSetup: hasCompletedInitialSetup
        )
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
        let resolvedProviderSetup: any ProviderSetupService
        if let providerSetup {
            resolvedProviderSetup = providerSetup
        } else {
            resolvedProviderSetup = MockProviderSetupService()
        }

        view = Self.makeView(
            thread: thread,
            appState: appState,
            context: context,
            recorder: recorder,
            services: ThreadDetailProjectTrustViewServices(
                settingsService: InMemorySettingsService(current: settings),
                providerSetup: resolvedProviderSetup
            )
        )
    }

    private static func makeSeededModel(
        isDraft: Bool,
        hasCompletedInitialSetup: Bool
    ) throws -> SeededModel {
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
        let thread = AgentThread(
            name: "Needs Trust",
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            isDraft: isDraft,
            project: project
        )
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
        recorder: ThreadDetailDeleteRecorder,
        services: ThreadDetailProjectTrustViewServices
    ) -> ThreadDetailView {
        let fileListManager = SnapshotMockFileListManager()
        let agentsManager = SidebarMockAgentsManager()
        let runtimeStore = MockConversationRuntimeStore()
        let worktreeManager = MockWorktreeManager(
            worktreeInfo: WorktreeInfo(path: "/tmp/alveary-worktree", branch: "main")
        )
        let contextWindowCache = MockContextWindowCache()
        let conversationControllerRegistry = DefaultConversationControllerRegistry { conversation in
            ConversationViewModel(
                conversation: conversation,
                agentsManager: agentsManager,
                runtimeStore: runtimeStore,
                keepAwakeService: RecordingKeepAwakeService(),
                modelContext: context,
                settingsService: services.settingsService,
                worktreeManager: worktreeManager,
                providerSetup: services.providerSetup,
                contextWindowCache: contextWindowCache
            )
        }
        return ThreadDetailView(
            thread: thread,
            appState: appState,
            modelContext: context,
            agentsManager: agentsManager,
            conversationControllerRegistry: conversationControllerRegistry,
            settingsService: services.settingsService,
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            providerDiscovery: SnapshotThreadProviderDiscoveryService(),
            providerSetup: services.providerSetup,
            contextWindowCache: contextWindowCache,
            fileListManager: fileListManager,
            notificationManager: RecordingNotificationManager(),
            availableProjects: thread.project.map { [$0] } ?? [],
            selectDraftProject: { _, _ in },
            deleteThread: { thread in
                try await recorder.delete(thread)
            },
            loadSkillCompletions: { [] },
            diffViewModel: DiffViewerViewModel(
                gitService: SnapshotMockGitService(statusResults: [[]], diffResults: [""]),
                fileListManager: fileListManager,
                agentsManager: agentsManager,
                fsEventDebounceDuration: .seconds(10),
                idlePollInterval: .seconds(10)
            )
        )
    }
}

private struct ThreadDetailProjectTrustViewServices {
    let settingsService: any SettingsService
    let providerSetup: any ProviderSetupService
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
