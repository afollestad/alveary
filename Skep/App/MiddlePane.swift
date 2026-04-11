import SwiftData
import SwiftUI

struct MiddlePane: View {
    @Bindable var appState: AppState
    let modelContext: ModelContext
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let agentRegistry: AgentRegistry
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let fileListManager: FileListManager
    let skillsService: SkillsService
    let mcpService: MCPService
    let loadInstalledSkills: () async -> [Skill]
    let diffViewModel: DiffViewerViewModel

    @Binding var skillsViewModel: SkillsViewModel?
    @Binding var mcpViewModel: MCPViewModel?
    @Binding var settingsViewModel: SettingsViewModel?

    @Environment(\.modelContext) private var uiModelContext
    @Query private var projects: [Project]

    var body: some View {
        switch appState.selectedSidebarItem {
        case .skills:
            SkillsScreen(viewModel: resolveSkillsViewModel())
        case .mcp:
            MCPScreen(viewModel: resolveMCPViewModel())
        case .project(let project):
            ProjectSettingsView(
                project: project,
                gitHubCLI: gitHubCLI,
                providerDetection: providerDetection,
                agentRegistry: agentRegistry
            )
            .id(project.path)
        case .thread(let thread):
            ThreadDetailView(
                thread: thread,
                appState: appState,
                modelContext: modelContext,
                agentsManager: agentsManager,
                runtimeStore: runtimeStore,
                settingsService: settingsService,
                providerRegistry: providerRegistry,
                worktreeManager: worktreeManager,
                providerSetup: providerSetup,
                fileListManager: fileListManager,
                loadSkillCompletions: loadInstalledSkills,
                diffViewModel: diffViewModel
            )
                .id(thread.persistentModelID)
        case .settings:
            SettingsScreen(viewModel: resolveSettingsViewModel()) {
                appState.selectedSidebarItem = appState.previousSelection.flatMap(resolveSidebarBookmark(_:))
            }
        case nil:
            if projects.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    heading: "Add your first project",
                    subtext: "Open a Git repository to start working with AI agents.",
                    actions: [
                        .init(title: "Open Existing Repo...", style: .primary) {
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

private extension MiddlePane {
    func resolveSkillsViewModel() -> SkillsViewModel {
        if let skillsViewModel {
            return skillsViewModel
        }

        let created = SkillsViewModel(skillsService: skillsService)
        skillsViewModel = created
        return created
    }

    func resolveMCPViewModel() -> MCPViewModel {
        if let mcpViewModel {
            return mcpViewModel
        }

        let created = MCPViewModel(mcpService: mcpService)
        mcpViewModel = created
        return created
    }

    func resolveSettingsViewModel() -> SettingsViewModel {
        if let settingsViewModel {
            return settingsViewModel
        }

        let created = SettingsViewModel(settingsService: settingsService)
        settingsViewModel = created
        return created
    }

    func resolveSidebarBookmark(_ bookmark: AppState.SidebarBookmark) -> SidebarItem? {
        switch bookmark {
        case .skills:
            return .skills
        case .mcp:
            return .mcp
        case .projectPath(let path):
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
                project.path == path
            })
            guard let project = try? uiModelContext.fetch(descriptor).first else {
                return nil
            }
            return .project(project)
        case .threadId(let id):
            guard let thread = uiModelContext.model(for: id) as? AgentThread else {
                return nil
            }

            if thread.archivedAt != nil {
                return thread.project.map(SidebarItem.project)
            }
            return .thread(thread)
        }
    }
}
