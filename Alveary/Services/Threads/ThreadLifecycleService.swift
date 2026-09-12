import AgentCLIKit
import Foundation
import SwiftData

/// Settings a new project thread starts with. `name` omitted keeps the placeholder title so
/// provider auto-naming still applies; `pinned` requests a sidebar pin inside the creating save.
struct ProjectThreadSeed {
    let provider: String
    let permissionMode: String
    let model: String?
    let effort: String
    let isDraft: Bool
    let name: String?
    let pinned: Bool
    let workspaceSnapshot: WorkspaceSnapshot?
    let useWorktree: Bool?
    let sectionID: String?

    init(
        provider: String,
        permissionMode: String,
        model: String?,
        effort: String,
        isDraft: Bool,
        name: String? = nil,
        pinned: Bool = false,
        workspaceSnapshot: WorkspaceSnapshot? = nil,
        useWorktree: Bool? = nil,
        sectionID: String? = nil
    ) {
        self.provider = provider
        self.permissionMode = permissionMode
        self.model = model
        self.effort = effort
        self.isDraft = isDraft
        self.name = name
        self.pinned = pinned
        self.workspaceSnapshot = workspaceSnapshot
        self.useWorktree = useWorktree
        self.sectionID = sectionID
    }
}

/// Where a new Task thread renders in the sidebar. One case at a time on purpose: a custom
/// section and a project nesting are mutually exclusive placements, and an enum keeps a caller
/// from asking for both. Either reference crosses the caller's suspensions as a plain value and
/// is re-resolved inside the creating save.
enum TaskThreadSidebarPlacement: Equatable {
    /// The plain `Tasks` list — a Task with no membership already renders there.
    case tasks
    /// `SidebarSection.id` of the custom section the new thread starts in.
    case section(id: String)
    /// Stable `Project.id` of the project the new thread nests under. Placement
    /// only: the thread keeps its own private workspace and `.task` mode.
    case project(id: String)
}

/// Settings a new Task thread starts with. A Task owns a private workspace instead of a Project,
/// so `grantedRoots` is how it reaches anything outside that workspace; those paths must already
/// be canonical absolute folders, validated by the caller the way provider and model are.
struct TaskThreadSeed {
    let provider: String
    let permissionMode: String
    let model: String?
    let effort: String
    let isDraft: Bool
    let name: String?
    let pinned: Bool
    let grantedRoots: [String]
    /// A workspace the caller already resolved, for a Task that has to start somewhere specific —
    /// nil mints the usual private one. Whatever the caller supplies, it also owns: a failed
    /// insert rolls back without removing it, because a borrowed checkout belongs to someone else.
    let workspace: TaskWorkspaceDescriptor?
    /// Sidebar placement the caller has already validated; a row that vanished since then fails
    /// the insert rather than half-applying. A `.project` placement does not grant its folder —
    /// the caller decides that through `grantedRoots`.
    let placement: TaskThreadSidebarPlacement
    let workspaceSnapshot: WorkspaceSnapshot?

    init(
        provider: String,
        permissionMode: String,
        model: String?,
        effort: String,
        isDraft: Bool,
        name: String? = nil,
        pinned: Bool = false,
        grantedRoots: [String] = [],
        workspace: TaskWorkspaceDescriptor? = nil,
        placement: TaskThreadSidebarPlacement = .tasks,
        workspaceSnapshot: WorkspaceSnapshot? = nil
    ) {
        self.provider = provider
        self.permissionMode = permissionMode
        self.model = model
        self.effort = effort
        self.isDraft = isDraft
        self.name = name
        self.pinned = pinned
        self.grantedRoots = grantedRoots
        self.workspace = workspace
        self.placement = placement
        self.workspaceSnapshot = workspaceSnapshot
    }
}

/// App-scoped thread creation and archiving.
///
/// `SidebarViewModel` is per-window, so callers with no window — the `alveary_host` MCP tools —
/// cannot route through it. This service owns the durable half of those lifecycles (persistence,
/// runtime teardown, provider-session actions, notifications) and returns what the sidebar needs
/// to finish the UI half; `SidebarViewModel` delegates rather than keeping a second copy.
/// Drafts, restore, delete, fork, and selection routing stay view-side.
@MainActor
final class ThreadLifecycleService {
    typealias ScheduledTaskRunQuiescence = @MainActor (PersistentIdentifier) async throws -> Void

    let modelContext: ModelContext
    private let settingsService: SettingsService
    private let agentsManager: any AgentsManager
    // Reached from `ThreadLifecycleService+Archive.swift`.
    let providerSessionActionService: any ProviderSessionActionService
    let notificationManager: any NotificationManager
    let taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService
    private let invalidateConversationController: @MainActor (String) -> Void
    // Internal rather than private: the `+ScheduledAttachments` companion awaits it.
    let stopAndWaitForScheduledTaskRun: ScheduledTaskRunQuiescence
    private let saveThreadCreation: @MainActor (ModelContext) throws -> Void
    // Reached from `ThreadLifecycleService+Pinning.swift`.
    let savePendingSidebarChanges: @MainActor (ModelContext) throws -> Void
    let saveSidebarOrdering: @MainActor (ModelContext) throws -> Void
    /// Which conversations are mid-review-submit, so archive and delete can refuse. Defaults to the
    /// app-wide instance; tests pass their own over a private notification centre.
    let reviewSubmissionActivity: PullRequestReviewSubmissionActivity

    init(
        modelContext: ModelContext,
        settingsService: SettingsService,
        agentsManager: any AgentsManager,
        providerSessionActionService: any ProviderSessionActionService = NoopProviderSessionActionService(),
        notificationManager: any NotificationManager,
        taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService = DefaultTaskWorkspaceOwnershipService(),
        invalidateConversationController: @escaping @MainActor (String) -> Void = { _ in },
        stopAndWaitForScheduledTaskRun: @escaping ScheduledTaskRunQuiescence = { _ in },
        saveThreadCreation: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        savePendingSidebarChanges: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveSidebarOrdering: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        reviewSubmissionActivity: PullRequestReviewSubmissionActivity = .shared
    ) {
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.agentsManager = agentsManager
        self.providerSessionActionService = providerSessionActionService
        self.notificationManager = notificationManager
        self.taskWorkspaceOwnershipService = taskWorkspaceOwnershipService
        self.invalidateConversationController = invalidateConversationController
        self.stopAndWaitForScheduledTaskRun = stopAndWaitForScheduledTaskRun
        self.saveThreadCreation = saveThreadCreation
        self.savePendingSidebarChanges = savePendingSidebarChanges
        self.saveSidebarOrdering = saveSidebarOrdering
        self.reviewSubmissionActivity = reviewSubmissionActivity
    }

    func insertProjectThread(projectPath: String, seed: ProjectThreadSeed) throws -> AgentThread {
        guard let project = modelContext.resolveProject(path: projectPath) else {
            throw SidebarViewModelError.projectMissing
        }
        return try insertProjectThread(project: project, seed: seed)
    }

    func insertProjectThread(projectID: String, seed: ProjectThreadSeed) throws -> AgentThread {
        guard let project = modelContext.resolveProject(projectID: projectID) else { throw SidebarViewModelError.projectMissing }
        return try insertProjectThread(project: project, seed: seed)
    }

    func insertProjectThread(project: Project, seed: ProjectThreadSeed) throws -> AgentThread {
        try insertSourceThread(project: project, seed: seed)
    }

    /// An inherited source can outlive its sidebar project. Its frozen folders still seed an
    /// independent local/worktree thread; sidebar placement cannot change execution kind.
    func insertSourceThread(project: Project?, seed: ProjectThreadSeed) throws -> AgentThread {
        let snapshot = seed.workspaceSnapshot ?? project?.workspaceSnapshot() ?? WorkspaceSnapshot(primarySource: nil)
        guard let primary = snapshot.primarySource else {
            return try insertTaskThread(seed: TaskThreadSeed(
                provider: seed.provider, permissionMode: seed.permissionMode, model: seed.model, effort: seed.effort,
                isDraft: seed.isDraft, name: seed.name, pinned: seed.pinned, grantedRoots: snapshot.grants.map(\.path),
                placement: project.map { .project(id: $0.id) } ?? .tasks, workspaceSnapshot: snapshot
            ))
        }
        // Unrelated pending edits must reach the store before a failed insert rolls the context back.
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let thread = AgentThread(
            name: seed.name ?? "New thread",
            hasCustomName: seed.name != nil,
            permissionMode: seed.permissionMode,
            effort: seed.effort,
            model: seed.model,
            useWorktree: (seed.useWorktree ?? settingsService.current.createWorktreeByDefault) && primary.isGitRepository,
            isDraft: seed.isDraft,
            project: project
        )
        thread.mode = .project
        thread.workspaceSnapshot = snapshot
        let conversation = Conversation(
            provider: seed.provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        do {
            // A pinned project already absorbs its children, so the pin would be invisible and
            // normalization would clear it in the same commit.
            if project == nil, let sectionID = seed.sectionID { thread.customSection = try resolvedSeedSection(id: sectionID) }
            if seed.pinned, project?.isPinned != true {
                try SidebarPinOrdering.pin(thread, in: modelContext)
            }
            try saveThreadCreation(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        return thread
    }

    /// Creates a Task thread over a freshly minted private workspace, or over the one the seed
    /// carries.
    ///
    /// Unlike a Project thread, this puts a directory on disk before it persists anything, so a
    /// failed save has to remove that workspace again; an orphan would otherwise survive until the
    /// next launch's orphan sweep. Only a workspace *this* call minted is removed on failure — a
    /// seeded one may be a checkout another thread is still using.
    func insertTaskThread(seed: TaskThreadSeed) throws -> AgentThread {
        // Unrelated pending edits must reach the store before a failed insert rolls the context back.
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let workspace: TaskWorkspaceDescriptor
        let mintedWorkspace: TaskWorkspaceDescriptor?
        if let seeded = seed.workspace {
            workspace = seeded
            mintedWorkspace = nil
        } else {
            let created = try taskWorkspaceOwnershipService.createPrivateWorkspace()
            workspace = created
            mintedWorkspace = created
        }
        let thread = AgentThread(
            name: seed.name ?? AgentThread.untitledName,
            hasCustomName: seed.name != nil,
            permissionMode: seed.permissionMode,
            effort: seed.effort,
            model: seed.model,
            useWorktree: false,
            isDraft: seed.isDraft,
            mode: .task,
            taskWorkspaceDescriptor: grantedWorkspace(workspace, grantedRoots: seed.grantedRoots),
            project: nil
        )
        if let snapshot = seed.workspaceSnapshot { thread.workspaceSnapshot = snapshot }
        let conversation = Conversation(
            provider: seed.provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        do {
            try applySeedPlacement(seed, to: thread)
            try saveThreadCreation(modelContext)
        } catch {
            modelContext.rollback()
            if let mintedWorkspace {
                try? taskWorkspaceOwnershipService.removeOwnedWorkspace(mintedWorkspace)
            }
            throw error
        }
        return thread
    }

    func requireThread(id: PersistentIdentifier) throws -> AgentThread {
        guard let thread = modelContext.resolveThread(id: id) else {
            throw SidebarViewModelError.threadMissing
        }
        return thread
    }

    func makeThreadArchiveSnapshot(_ thread: AgentThread) throws -> ThreadArchiveSnapshot {
        let dbThread = try requireThread(id: thread.persistentModelID)
        let threadID = dbThread.persistentModelID
        return ThreadArchiveSnapshot(
            threadID: threadID,
            mode: dbThread.effectiveMode,
            conversationIDs: liveConversationIDs(for: threadID),
            providerSessionAction: providerSessionActionSnapshot(for: dbThread)
        )
    }

    func providerSessionActionSnapshot(for thread: AgentThread) -> ProviderSessionActionSnapshot {
        let threadID = thread.persistentModelID
        let workingDirectory = thread.primaryWorkingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return ProviderSessionActionSnapshot(
            conversations: liveConversations(for: threadID).map {
                ProviderSessionConversationSnapshot(
                    conversationID: $0.id,
                    providerID: $0.provider,
                    providerSessionID: $0.providerSessionId,
                    providerSessionProviderID: $0.providerSessionProviderId,
                    providerSessionWorkingDirectory: $0.providerSessionWorkingDirectory,
                    hasStartedProviderSession: thread.hasCompletedInitialSetup
                )
            },
            workingDirectory: workingDirectory
        )
    }

    func liveConversationIDs(for threadID: PersistentIdentifier) -> [String] {
        liveConversations(for: threadID).map(\.id)
    }

    func invalidateConversationControllers(_ conversationIDs: [String]) {
        for conversationID in conversationIDs {
            invalidateConversationController(conversationID)
        }
    }

    func postThreadLifecycleChanged(threadID: PersistentIdentifier, mode: AgentThreadMode) {
        NotificationCenter.default.post(
            name: .threadLifecycleChanged,
            object: nil,
            userInfo: [
                ThreadLifecycleNotificationKey.threadID: threadID,
                ThreadLifecycleNotificationKey.mode: mode.rawValue
            ]
        )
    }

    func backfillProviderSessionBindings(from records: [AgentCLIKit.AgentSessionRecord]) throws {
        guard !records.isEmpty else {
            return
        }

        for record in records {
            guard let conversation = modelContext.resolveConversation(conversationID: record.conversationId.rawValue) else {
                continue
            }
            conversation.providerSessionId = record.providerSessionId.rawValue
            conversation.providerSessionProviderId = record.providerId.rawValue
            conversation.providerSessionWorkingDirectory = record.workingDirectory?.path
        }
        try modelContext.save()
    }

    func beginConversationTeardowns(_ conversationIDs: [String]) async {
        for conversationId in uniqueConversationIDs(conversationIDs) {
            NotificationCenter.default.post(name: .reviewTeamConversationWillClose, object: nil,
                                            userInfo: ["conversationID": conversationId])
            await agentsManager.kill(conversationId: conversationId)
        }
    }

    func conversationTeardownError(_ conversationIDs: [String]) async -> Error? {
        do {
            try await awaitConversationTeardowns(conversationIDs)
            return nil
        } catch {
            return error
        }
    }

    func awaitConversationTeardowns(_ conversationIDs: [String]) async throws {
        let conversationIDs = uniqueConversationIDs(conversationIDs)
        let agentsManager = agentsManager
        var errors = [Error?](repeating: nil, count: conversationIDs.count)

        await withTaskGroup(of: (Int, Error?).self) { group in
            for (index, conversationId) in conversationIDs.enumerated() {
                group.addTask {
                    do {
                        try await agentsManager.destroyRuntime(conversationId: conversationId)
                        return (index, nil)
                    } catch { return (index, error) }
                }
            }

            for await (index, error) in group {
                errors[index] = error
            }
        }

        if let firstError = errors.compactMap({ $0 }).first {
            throw firstError
        }
    }

    func uniqueConversationIDs(_ conversationIDs: [String]) -> [String] {
        var seen = Set<String>()
        return conversationIDs.filter { seen.insert($0).inserted }
    }

    /// Applies a Task seed's pin and sidebar placement, inside the creating save so membership
    /// commits atomically with the thread.
    private func applySeedPlacement(_ seed: TaskThreadSeed, to thread: AgentThread) throws {
        let placementProject = try resolvedSeedProject(for: seed.placement)
        // A pinned project already absorbs its children, so that pin would be invisible and
        // normalization would clear it in the same commit; every other placement carries one.
        if seed.pinned, placementProject?.isPinned != true {
            try SidebarPinOrdering.pin(thread, in: modelContext)
        }
        switch seed.placement {
        case .tasks:
            break
        case .section(let sectionID):
            thread.customSection = try resolvedSeedSection(id: sectionID)
        case .project:
            thread.project = placementProject
        }
    }

    /// Membership commits atomically with the thread; a section that vanished since the caller
    /// validated it fails the whole insert rather than half-applying.
    private func resolvedSeedSection(id: String) throws -> SidebarSection {
        guard let section = modelContext.resolveSidebarSection(id: id),
              section.kind == .custom else {
            throw SidebarSectionServiceError.sectionMissing
        }
        return section
    }

    /// The `.project` placement's row, resolved before the pin decision because a pinned project
    /// absorbs its children's pins. Vanishing since the caller validated it fails the whole
    /// insert, mirroring `resolvedSeedSection`; nil just means a non-project placement.
    private func resolvedSeedProject(for placement: TaskThreadSidebarPlacement) throws -> Project? {
        guard case .project(let id) = placement else {
            return nil
        }
        guard let project = modelContext.resolveProject(projectID: id) else {
            throw SidebarViewModelError.projectMissing
        }
        return project
    }

    /// The caller already canonicalized these paths, so they are rehydrated rather than resolved
    /// again: a second resolution could follow a symlink swapped in since validation, granting a
    /// folder other than the one that was checked.
    private func grantedWorkspace(
        _ workspace: TaskWorkspaceDescriptor,
        grantedRoots: [String]
    ) -> TaskWorkspaceDescriptor {
        guard !grantedRoots.isEmpty else {
            return workspace
        }
        return TaskWorkspaceDescriptor(
            persistedPrimaryRoot: workspace.primaryRoot,
            persistedGrantedRoots: grantedRoots.filter { $0 != workspace.primaryRoot },
            ownershipStrategy: workspace.ownershipStrategy,
            ownershipMarkerID: workspace.ownershipMarkerID,
            persistedSourceProjectPath: workspace.sourceProjectPath
        )
    }

    private func liveConversations(for threadID: PersistentIdentifier) -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
