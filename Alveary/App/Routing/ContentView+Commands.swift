import AppKit
import SwiftData
import SwiftUI

struct NewThreadProjectResolution {
    let project: Project?
    let lastActiveProjectID: String?

    init(project: Project?) {
        self.project = project
        self.lastActiveProjectID = project?.id
    }
}

@MainActor
enum NewThreadProjectResolver {
    static func resolve(
        selection: SidebarItem?,
        previousSelection: AppState.SidebarBookmark?,
        lastActiveProjectID: String?,
        legacyProjectPath: String? = nil,
        modelContext: ModelContext
    ) -> NewThreadProjectResolution {
        if let current = currentProject(
            selection: selection,
            previousSelection: previousSelection,
            modelContext: modelContext
        ) {
            return NewThreadProjectResolution(project: current)
        }

        if let lastActiveProjectID,
           let lastActive = modelContext.resolveProject(projectID: lastActiveProjectID) {
            return NewThreadProjectResolution(project: lastActive)
        }

        if let legacyProjectPath, let legacy = modelContext.resolveProject(path: legacyProjectPath) {
            return NewThreadProjectResolution(project: legacy)
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
            guard let thread = modelContext.resolveThread(id: thread.persistentModelID) else {
                return nil
            }
            return thread.project
        case .settings:
            guard let previousSelection else {
                return nil
            }

            switch previousSelection {
            case .projectID(let id):
                return modelContext.resolveProject(id: id)
            case .threadId(let id):
                guard let thread = modelContext.resolveThread(id: id) else {
                    return nil
                }
                return thread.project
            case .skills, .mcp, .scheduled, .pullRequests, .archived:
                return nil
            }
        case .skills, .mcp, .scheduled, .pullRequests, .archived, nil:
            return nil
        }
    }

}

extension ContentView {
    func handlePendingCommand(_ command: AppState.CommandRequest?) {
        guard let command,
              !voiceInputLifecycleController.isModelPreparationModalPresented else {
            return
        }

        let commandID = command.id
        Task { @MainActor in
            var shouldClearCommand = false
            defer {
                if shouldClearCommand,
                   appState.pendingCommand?.id == commandID {
                    appState.pendingCommand = nil
                }
            }

            guard pendingCommandCanProceed(
                commandID: commandID,
                currentCommandID: appState.pendingCommand?.id,
                isModelPreparationModalPresented: voiceInputLifecycleController.isModelPreparationModalPresented
            ) else {
                return
            }

            switch command {
            case .newProject:
                isAddProjectSheetPresented = true
                shouldClearCommand = true

            case .newThread(_, let destination):
                shouldClearCommand = await handleNewThreadCommand(commandID: commandID, destination: destination)
            }
        }
    }

    @ViewBuilder
    func addProjectSheetContent() -> some View {
        AddProjectSheet(
            viewModel: sidebarViewModel,
            settingsService: settingsService,
            onProjectCreated: { project in
                isAddProjectSheetPresented = false
                appState.selectedSidebarItem = resolveProject(projectID: project.id)
                    .map(SidebarItem.project)
            }
        )
    }
}

@MainActor
@discardableResult
func performAppNavigationIfModelPreparationModalAbsent(
    lifecycleController: VoiceInputLifecycleController,
    operation: () -> Void
) -> Bool {
    guard !lifecycleController.isModelPreparationModalPresented else {
        return false
    }
    operation()
    return true
}

func pendingCommandCanProceed(
    commandID: UUID,
    currentCommandID: UUID?,
    isModelPreparationModalPresented: Bool
) -> Bool {
    currentCommandID == commandID && !isModelPreparationModalPresented
}

extension ContentView {
    func resolveProject(projectID: String) -> Project? {
        uiModelContext.resolveProject(projectID: projectID)
    }

    @discardableResult
    func handleNewThreadCommand(commandID: UUID, destination: ThreadDraftDestination?) async -> Bool {
        do {
            let createdThread = try await sidebarViewModel.openDraft(destination: destination ?? resolvedNewThreadDestination())
            guard pendingCommandCanProceed(
                commandID: commandID,
                currentCommandID: appState.pendingCommand?.id,
                isModelPreparationModalPresented: voiceInputLifecycleController.isModelPreparationModalPresented
            ) else {
                return false
            }

            appState.requestComposerFocus()
            appState.selectedSidebarItem = uiModelContext.resolveThread(id: createdThread.persistentModelID).map(SidebarItem.thread)
            return true
        } catch {
            guard pendingCommandCanProceed(
                commandID: commandID,
                currentCommandID: appState.pendingCommand?.id,
                isModelPreparationModalPresented: voiceInputLifecycleController.isModelPreparationModalPresented
            ) else {
                return false
            }
            sidebarViewModel.presentSidebarError(error)
            return true
        }
    }

    func resolvedNewThreadDestination() -> ThreadDraftDestination {
        // A selected standalone thread keeps its placement; a previous project is only a fallback on other screens.
        if case .thread(let selected) = appState.selectedSidebarItem,
           let thread = uiModelContext.resolveThread(id: selected.persistentModelID) {
            if let project = thread.project { return .project(id: project.id) }
            if let section = thread.customSection { return .section(id: section.id) }
            return .tasks
        }
        return resolvedNewThreadProject().map { .project(id: $0.id) } ?? .tasks
    }

    func resolvedNewThreadProject() -> Project? {
        let resolution = NewThreadProjectResolver.resolve(
            selection: appState.selectedSidebarItem,
            previousSelection: appState.previousSelection,
            lastActiveProjectID: settingsService.current.lastActiveProjectID,
            legacyProjectPath: settingsService.current.lastActiveProjectPath,
            modelContext: uiModelContext
        )
        settingsService.updateLastActiveProjectID(resolution.lastActiveProjectID)
        return resolution.project
    }

    func scheduleLastActiveProjectRecord(for selection: SidebarItem?) {
        lastActiveProjectRecorder.record(for: selection)
    }

}
