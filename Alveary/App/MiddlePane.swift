import AgentCLIKit
import SwiftData
import SwiftUI

struct MiddlePane: View {
    @Bindable var appState: AppState
    let modelContext: ModelContext
    let gitHubCLI: GitHubCLIService
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let attachmentStore: any ConversationAttachmentStore
    let keepAwakeService: KeepAwakeService
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let threadActivityRecorder: any ThreadActivityRecording
    let sidebarViewModel: SidebarViewModel
    let loadInstalledSkills: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    let skillsViewModel: SkillsViewModel
    let mcpViewModel: MCPViewModel
    let settingsViewModel: SettingsViewModel
    let appShotCoordinator: AppShotCoordinator
    let appUpdateManager: AppUpdateManager
    let targetSettingsPage: AppSettings.SettingsPage?
    let onTargetSettingsPageHandled: (AppSettings.SettingsPage) -> Void

    @Environment(\.modelContext) private var uiModelContext
    @Query private var projects: [Project]

    var body: some View {
        switch appState.selectedSidebarItem {
        case .skills:
            SkillsScreen(viewModel: skillsViewModel)
        case .mcp:
            MCPScreen(viewModel: mcpViewModel)
        case .project(let project):
            ProjectSettingsView(
                project: project,
                appState: appState,
                sidebarViewModel: sidebarViewModel
            )
                .id(project.path)
        case .thread(let thread):
            ThreadDetailView(
                thread: thread,
                appState: appState,
                modelContext: modelContext,
                agentsManager: agentsManager,
                runtimeStore: runtimeStore,
                attachmentStore: attachmentStore,
                keepAwakeService: keepAwakeService,
                settingsService: settingsService,
                providerRegistry: providerRegistry,
                providerDiscovery: providerDiscovery,
                worktreeManager: worktreeManager,
                providerSetup: providerSetup,
                contextWindowCache: contextWindowCache,
                fileListManager: fileListManager,
                notificationManager: notificationManager,
                threadActivityRecorder: threadActivityRecorder,
                availableProjects: projects,
                selectDraftProject: { threadID, projectPath in
                    do {
                        let draft = try sidebarViewModel.moveDraftThread(id: threadID, toProjectPath: projectPath)
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
                appShotCoordinator: appShotCoordinator
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
            }
        }
    }
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

        if thread.archivedAt != nil {
            return thread.project.map(SidebarItem.project)
        }
        return .thread(thread)
    }
}

private extension MiddlePane {
    func resolveSidebarBookmark(_ bookmark: AppState.SidebarBookmark) -> SidebarItem? {
        resolveSidebarSelectionBookmark(bookmark, modelContext: uiModelContext)
    }
}
