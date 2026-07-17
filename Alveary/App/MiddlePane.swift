import AgentCLIKit
import SwiftData
import SwiftUI

struct MiddlePane: View {
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
    let skillsViewModel: SkillsViewModel
    let mcpViewModel: MCPViewModel
    let scheduledTasksViewModel: ScheduledTasksViewModel
    let settingsViewModel: SettingsViewModel
    let archivedTasksSettingsViewModel: ArchivedTasksSettingsViewModel
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
        case .scheduled:
            ScheduledTasksScreen(viewModel: scheduledTasksViewModel)
        case .project(let project):
            ProjectSettingsView(
                project: project,
                appState: appState,
                sidebarViewModel: sidebarViewModel,
                voiceInputLifecycleController: voiceInputLifecycleController
            )
                .id(project.path)
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
                diffViewModel: diffViewModel
            )
                .id(thread.persistentModelID)
        case .settings:
            SettingsScreen(
                viewModel: settingsViewModel,
                archivedTasksViewModel: archivedTasksSettingsViewModel,
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

        if thread.archivedAt != nil, thread.effectiveMode == .project {
            return thread.project.map(SidebarItem.project)
        }
        guard thread.archivedAt == nil else {
            return nil
        }
        return .thread(thread)
    }
}

private extension MiddlePane {
    func resolveSidebarBookmark(_ bookmark: AppState.SidebarBookmark) -> SidebarItem? {
        resolveSidebarSelectionBookmark(bookmark, modelContext: uiModelContext)
    }
}
