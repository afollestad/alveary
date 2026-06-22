import AppKit
import SwiftData
import SwiftUI

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
        guard let project = currentProjectContext() else {
            return
        }

        do {
            let createdThread = try await sidebarViewModel.createThread(project: project)
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

    func currentProjectContext() -> Project? {
        switch appState.selectedSidebarItem {
        case .project(let project):
            return project
        case .thread(let thread):
            return thread.project
        case .settings:
            guard let bookmark = appState.previousSelection else {
                return nil
            }

            switch bookmark {
            case .projectPath(let path):
                return resolveProject(path: path)
            case .threadId(let id):
                return uiModelContext.resolveThread(id: id)?.project
            case .skills, .mcp:
                return nil
            }
        default:
            return nil
        }
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
