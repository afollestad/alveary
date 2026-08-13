import AppKit
import Foundation
import SwiftData
import SwiftUI

@testable import Alveary

actor PausingThreadDetailProjectTrustService: ProviderSetupService {
    private let pausedProjectPath: String
    private var didPauseStatus = false
    private var statusPauseContinuation: CheckedContinuation<Void, Never>?
    private var statusPauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var trustedProjectPaths = Set<String>()

    init(pausedProjectPath: String) {
        self.pausedProjectPath = CanonicalPath.normalize(pausedProjectPath)
    }

    nonisolated func cachedProjectTrustStatus(providerId _: String, workingDirectory _: String) -> Bool? {
        nil
    }

    func projectTrustUpdates() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func prepareForSpawn(providerId _: String, workingDirectory _: String, autoTrust _: Bool) async {}

    func isTrustedProject(providerId _: String, workingDirectory: String) async -> Bool {
        let projectPath = CanonicalPath.normalize(workingDirectory)
        if projectPath == pausedProjectPath, !didPauseStatus {
            didPauseStatus = true
            statusPauseWaiters.forEach { $0.resume() }
            statusPauseWaiters.removeAll()
            await withCheckedContinuation { statusPauseContinuation = $0 }
        }
        return trustedProjectPaths.contains(projectPath)
    }

    func trustProject(providerId _: String, workingDirectory: String) async {
        trustedProjectPaths.insert(CanonicalPath.normalize(workingDirectory))
    }

    func waitUntilStatusPaused() async {
        guard !didPauseStatus else {
            return
        }
        await withCheckedContinuation { statusPauseWaiters.append($0) }
    }

    func resumePausedStatus() {
        statusPauseContinuation?.resume()
        statusPauseContinuation = nil
    }

    func recordedTrustedProjectPaths() -> Set<String> {
        trustedProjectPaths
    }
}

enum ThreadDetailProjectTrustError: LocalizedError {
    case cleanupFailed

    var errorDescription: String? {
        "Cleanup failed"
    }
}

final class ThreadDetailVoiceModelModalSink: VoiceInputComposerSink {
    var isModelPreparationModalPresented: Bool { true }

    func forceVoiceInputCommitSynchronously() {}
}

@MainActor
struct ThreadDetailProjectTrustFixture {
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
    ) throws -> ThreadDetailProjectTrustSeededModel {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
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
        return ThreadDetailProjectTrustSeededModel(
            container: container,
            context: context,
            project: project,
            thread: thread,
            conversation: conversation
        )
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
        let voiceInputService = DisabledVoiceInputService()
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
            voiceInputService: voiceInputService,
            voiceInputLifecycleController: VoiceInputLifecycleController(service: voiceInputService),
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

struct ThreadDetailProjectTrustViewServices {
    let settingsService: any SettingsService
    let providerSetup: any ProviderSetupService
}

struct ThreadDetailProjectTrustSeededModel {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
}

@MainActor
final class ThreadDetailDeleteRecorder {
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
