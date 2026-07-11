import AppKit
import SwiftData
import SwiftUI

enum NewThreadCommandPresentation {
    static let noProjectMessage = "Add a project before starting a new thread."
}

struct NewThreadProjectResolution {
    let project: Project?
    let lastActiveProjectPath: String?

    init(project: Project?) {
        self.project = project
        self.lastActiveProjectPath = project?.path
    }
}

@MainActor
enum NewThreadProjectResolver {
    static func resolve(
        selection: SidebarItem?,
        previousSelection: AppState.SidebarBookmark?,
        lastActiveProjectPath: String?,
        modelContext: ModelContext
    ) -> NewThreadProjectResolution {
        if let current = currentProject(
            selection: selection,
            previousSelection: previousSelection,
            modelContext: modelContext
        ) {
            return NewThreadProjectResolution(project: current)
        }

        if let lastActiveProjectPath,
           let lastActive = project(path: lastActiveProjectPath, modelContext: modelContext) {
            return NewThreadProjectResolution(project: lastActive)
        }

        let descriptor = FetchDescriptor<Project>()
        let fallback = ((try? modelContext.fetch(descriptor)) ?? []).sorted(by: areProjectsOrdered).first
        return NewThreadProjectResolution(project: fallback)
    }

    static func currentProject(
        selection: SidebarItem?,
        previousSelection: AppState.SidebarBookmark?,
        modelContext: ModelContext
    ) -> Project? {
        switch selection {
        case .project(let project):
            return modelContext.resolveProject(id: project.persistentModelID)
        case .thread(let thread):
            return modelContext.resolveThread(id: thread.persistentModelID)?.project
        case .settings:
            guard let previousSelection else {
                return nil
            }

            switch previousSelection {
            case .projectPath(let path):
                return project(path: path, modelContext: modelContext)
            case .threadId(let id):
                return modelContext.resolveThread(id: id)?.project
            case .skills, .mcp:
                return nil
            }
        case .skills, .mcp, nil:
            return nil
        }
    }

    private static func project(path: String, modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        return try? modelContext.fetch(descriptor).first
    }
}

extension ContentView {
    func handlePendingCommand(_ command: AppState.CommandRequest?) {
        guard let command else {
            return
        }

        let commandID = command.id
        Task { @MainActor in
            defer {
                if appState.pendingCommand?.id == commandID {
                    appState.pendingCommand = nil
                }
            }

            switch command {
            case .newProject:
                isAddProjectSheetPresented = true

            case .newThread:
                await handleNewThreadCommand(commandID: commandID)
            }
        }
    }

    func handleAddProjectSheetDismiss() {
        guard pendingDiskImportAfterDismiss else {
            return
        }
        pendingDiskImportAfterDismiss = false
        Task { @MainActor in
            await importProjectFromDisk()
        }
    }

    @ViewBuilder
    func addProjectSheetContent() -> some View {
        AddProjectSheet(
            viewModel: sidebarViewModel,
            settingsService: settingsService,
            onChooseFromDisk: {
                pendingDiskImportAfterDismiss = true
                isAddProjectSheetPresented = false
            },
            onProjectCreated: { project in
                isAddProjectSheetPresented = false
                appState.selectedSidebarItem = resolveProject(path: project.path)
                    .map(SidebarItem.project)
            }
        )
    }
}

extension ContentView {
    func resolveProject(path: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        return try? uiModelContext.fetch(descriptor).first
    }

    func handleNewThreadCommand(commandID: UUID) async {
        guard let project = resolvedNewThreadProject() else {
            appState.presentUnexpectedError(message: NewThreadCommandPresentation.noProjectMessage)
            return
        }

        do {
            let createdThread = try await sidebarViewModel.openDraftThread(project: project)
            guard appState.pendingCommand?.id == commandID else {
                return
            }

            appState.requestComposerFocus()
            appState.selectedSidebarItem = uiModelContext.resolveThread(id: createdThread.persistentModelID).map(SidebarItem.thread)
        } catch {
            guard appState.pendingCommand?.id == commandID else {
                return
            }
            sidebarViewModel.presentSidebarError(error)
        }
    }

    func resolvedNewThreadProject() -> Project? {
        let resolution = NewThreadProjectResolver.resolve(
            selection: appState.selectedSidebarItem,
            previousSelection: appState.previousSelection,
            lastActiveProjectPath: settingsService.current.lastActiveProjectPath,
            modelContext: uiModelContext
        )
        settingsService.updateLastActiveProjectPath(resolution.lastActiveProjectPath)
        return resolution.project
    }

    func recordLastActiveProject(for selection: SidebarItem?) {
        let path: String?
        switch selection {
        case .project(let project):
            path = uiModelContext.resolveProject(id: project.persistentModelID)?.path
        case .thread(let thread):
            path = uiModelContext.resolveThread(id: thread.persistentModelID)?.project?.path
        default:
            return
        }
        settingsService.updateLastActiveProjectPath(path)
    }

    func importProjectFromDisk() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let createdProject = try await sidebarViewModel.createProject(path: url.path)
            appState.selectedSidebarItem = resolveProject(path: createdProject.path)
                .map(SidebarItem.project)
        } catch {
            sidebarViewModel.presentSidebarError(error)
        }
    }
}
