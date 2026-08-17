import AgentCLIKit
import SwiftData
import SwiftUI

/// The middle pane compares equal across root render passes, which is the only memoization
/// boundary between `ContentView` and the visible screen. Without it every root
/// invalidation — a toolbar badge, a diff-stat tick, a pane-session write, each frame of a
/// right-pane resize drag — rebuilt this whole subtree.
struct MiddlePane: View, Equatable {
    @Bindable var appState: AppState
    let modelContext: ModelContext
    let gitHubCLI: GitHubCLIService
    let agentsManager: any AgentsManager
    let conversationControllerRegistry: any ConversationControllerRegistry
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let voiceInputService: any VoiceInputService
    let voiceInputLifecycleController: VoiceInputLifecycleController
    let sidebarViewModel: SidebarViewModel
    let loadInstalledSkills: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    let diffViewerSwitchScope: @MainActor () -> DiffViewerSwitchScope
    let skillsViewModel: SkillsViewModel
    let mcpViewModel: MCPViewModel
    let scheduledTasksViewModel: ScheduledTasksViewModel
    let pullRequestsViewModel: PullRequestsViewModel
    let settingsViewModel: SettingsViewModel
    let archivedThreadsViewModel: ArchivedThreadsViewModel
    let appUpdateManager: AppUpdateManager
    let targetSettingsPage: AppSettings.SettingsPage?
    let onTargetSettingsPageHandled: (AppSettings.SettingsPage) -> Void

    @Environment(\.modelContext) private var uiModelContext
    @Query private var projects: [Project]

    // Match the new-thread hero's optical center within the root selection pane.
    private let selectionEmptyStateVerticalOffset: CGFloat = -86

    /// `targetSettingsPage` is the only stored input that varies; everything the body
    /// renders otherwise comes from `appState`, the `@Query`, and the environment, all of
    /// which invalidate this view directly. The services are dependency handles
    /// `ContentView` injects once per window, and the three closures read through those
    /// same references and `@State` boxes rather than a captured copy's stored values, so
    /// freezing them cannot serve a stale answer. `appState` and `modelContext` are
    /// omitted only because a `nonisolated` `==` cannot read them; they are injected once
    /// per window like the rest.
    nonisolated static func == (lhs: MiddlePane, rhs: MiddlePane) -> Bool {
        lhs.targetSettingsPage == rhs.targetSettingsPage && sameViewModels(lhs, rhs)
    }

    private nonisolated static func sameViewModels(_ lhs: MiddlePane, _ rhs: MiddlePane) -> Bool {
        lhs.sidebarViewModel === rhs.sidebarViewModel
            && lhs.diffViewModel === rhs.diffViewModel
            && lhs.skillsViewModel === rhs.skillsViewModel
            && lhs.mcpViewModel === rhs.mcpViewModel
            && lhs.scheduledTasksViewModel === rhs.scheduledTasksViewModel
            && lhs.pullRequestsViewModel === rhs.pullRequestsViewModel
            && lhs.settingsViewModel === rhs.settingsViewModel
            && lhs.archivedThreadsViewModel === rhs.archivedThreadsViewModel
            && lhs.appUpdateManager === rhs.appUpdateManager
    }

    var body: some View {
        switch appState.selectedSidebarItem {
        case .skills:
            SkillsScreen(viewModel: skillsViewModel)
        case .mcp:
            MCPScreen(viewModel: mcpViewModel)
        case .scheduled:
            ScheduledTasksScreen(viewModel: scheduledTasksViewModel)
        case .pullRequests:
            PullRequestsScreen(
                viewModel: pullRequestsViewModel,
                onOpenGitSettings: { appState.openSettings(targetPage: .git) }
            )
        case .archived:
            ArchivedScreen(viewModel: archivedThreadsViewModel)
        case .project(let project):
            // A selection is a token, not proof of liveness (`SidebarItem.resolved(in:)`'s
            // contract): reading `path` off a deleted row traps inside SwiftData, so re-resolve
            // first and render a gone row as no selection.
            if case .project(let liveProject)? = SidebarItem.project(project).resolved(in: modelContext) {
                // `.id` gives each project a fresh editor, so a revisited project would
                // start empty and fill in a beat later; the cached config (an in-memory
                // lookup, no I/O) lets it render populated on this frame instead.
                ProjectSettingsView(
                    project: liveProject,
                    appState: appState,
                    sidebarViewModel: sidebarViewModel,
                    initialConfig: ProjectConfigStore.shared.cached(forProjectPath: liveProject.path) ?? .empty
                )
                    .id(liveProject.path)
            } else {
                noSelectionPane
            }
        case .thread(let thread):
            ThreadDetailView(
                thread: thread,
                appState: appState,
                modelContext: modelContext,
                agentsManager: agentsManager,
                conversationControllerRegistry: conversationControllerRegistry,
                settingsService: settingsService,
                providerRegistry: providerRegistry,
                providerDiscovery: providerDiscovery,
                providerSetup: providerSetup,
                contextWindowCache: contextWindowCache,
                fileListManager: fileListManager,
                notificationManager: notificationManager,
                voiceInputService: voiceInputService,
                voiceInputLifecycleController: voiceInputLifecycleController,
                availableProjects: projects,
                selectDraftProject: { threadID, projectPath in
                    do {
                        guard let draft = try performDraftProjectMoveIfVoiceInputUnlocked(
                            lifecycleController: voiceInputLifecycleController,
                            operation: {
                                try sidebarViewModel.moveDraftThread(id: threadID, toProjectPath: projectPath)
                            }
                        ) else {
                            return
                        }
                        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
                              selectedThread.persistentModelID == threadID else {
                            return
                        }
                        appState.requestComposerFocus()
                        appState.selectedSidebarItem = .thread(draft)
                    } catch {
                        sidebarViewModel.presentSidebarError(error)
                    }
                },
                deleteThread: { thread in
                    try await sidebarViewModel.deleteThread(thread)
                },
                loadSkillCompletions: loadInstalledSkills,
                diffViewModel: diffViewModel,
                diffViewerSwitchScope: diffViewerSwitchScope
            )
                .id(thread.persistentModelID)
        case .settings:
            SettingsScreen(
                viewModel: settingsViewModel,
                gitHubCLI: gitHubCLI,
                appUpdateManager: appUpdateManager,
                targetPage: targetSettingsPage,
                onTargetPageHandled: onTargetSettingsPageHandled
            ) {
                appState.selectedSidebarItem = appState.previousSelection.flatMap(resolveSidebarBookmark(_:))
            }
        case nil:
            noSelectionPane
        }
    }

    /// Also the fallback for a `.project` selection whose row a delete removed before the
    /// selection routed away.
    @ViewBuilder
    private var noSelectionPane: some View {
        if projects.isEmpty {
            EmptyStateView(
                icon: "folder.badge.plus",
                heading: "Add your first project",
                subtext: "Open a project folder to start working with AI agents.",
                actions: [
                    .init(
                        title: "Add Project...",
                        style: .primary,
                        helpText: "Add Project... (\(KeyboardShortcut.addProject.displayString))"
                    ) {
                        appState.openNewProjectFlow()
                    }
                ]
            )
        } else {
            EmptyStateView(
                icon: "sidebar.left",
                heading: "Select a project or thread",
                subtext: "Choose something from the sidebar to continue.",
                actions: []
            )
            .offset(y: selectionEmptyStateVerticalOffset)
        }
    }
}

@MainActor
func performDraftProjectMoveIfVoiceInputUnlocked<Result>(
    lifecycleController: VoiceInputLifecycleController,
    operation: () throws -> Result
) rethrows -> Result? {
    guard !lifecycleController.isComposerInteractionLocked else { return nil }
    return try operation()
}

func resolveSidebarSelectionBookmark(
    _ bookmark: AppState.SidebarBookmark,
    modelContext: ModelContext
) -> SidebarItem? {
    switch bookmark {
    case .skills:
        return .skills
    case .mcp:
        return .mcp
    case .scheduled:
        return .scheduled
    case .pullRequests:
        return .pullRequests
    case .archived:
        return .archived
    case .projectPath(let path):
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        guard let project = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        return .project(project)
    case .threadId(let id):
        guard let thread = modelContext.resolveThread(id: id) else {
            return nil
        }

        // Any archived thread with a project falls back to that project's row, including a
        // Task that was placed in one.
        if thread.archivedAt != nil {
            return thread.project.map(SidebarItem.project)
        }
        return .thread(thread)
    }
}

/// A hidden `Pull requests` row leaves the screen unreachable, so a bookmark that still points at
/// it must not restore it. Applied where Settings hands selection back.
func sidebarSelectionAllowingHiddenPullRequests(
    _ item: SidebarItem?,
    showsPullRequests: Bool
) -> SidebarItem? {
    guard item == .pullRequests, !showsPullRequests else {
        return item
    }
    return nil
}

private extension MiddlePane {
    func resolveSidebarBookmark(_ bookmark: AppState.SidebarBookmark) -> SidebarItem? {
        sidebarSelectionAllowingHiddenPullRequests(
            resolveSidebarSelectionBookmark(bookmark, modelContext: uiModelContext),
            showsPullRequests: settingsService.current.pullRequestsEnabled
        )
    }
}
