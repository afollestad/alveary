import AgentCLIKit
import Foundation
import Observation
import SwiftData

enum ScheduledTasksViewModelError: Error, LocalizedError {
    case titleRequired
    case promptRequired
    case projectRequired
    case projectNotFound
    case runNowRejected

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a title for the scheduled task."
        case .promptRequired:
            "Enter instructions for the scheduled task."
        case .projectRequired:
            "Choose a project for this scheduled task."
        case .projectNotFound:
            "The selected project no longer exists."
        case .runNowRejected:
            "This scheduled task could not be started. It may already be starting or the scheduler may be unavailable."
        }
    }
}

@MainActor
@Observable
final class ScheduledTasksViewModel {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let mutationService: ScheduledTaskMutationService
    @ObservationIgnored let providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)?
    @ObservationIgnored let settingsService: any SettingsService
    @ObservationIgnored let agentRegistry: AgentRegistry
    @ObservationIgnored private let runNowAction: @MainActor (ScheduledTaskRunNowRequest) -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var changeObservationTask: Task<Void, Never>?

    private(set) var tasks: [ScheduledTaskRowPresentation] = []
    private(set) var projects: [ScheduledTaskProjectOption] = []
    var providerStatuses: [String: AgentCLIKit.AgentProviderStatus] = [:]
    var providerOrdering: [String] = []
    var isLoadingProviders = false
    private(set) var pendingRunNowDefinitionIDs = Set<String>()
    private(set) var pendingEditorDraft: ScheduledTaskEditorDraft?
    private(set) var editorErrorMessage: String?
    var errorMessage: String?

    init(
        modelContext: ModelContext,
        mutationService: ScheduledTaskMutationService,
        providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)? = nil,
        settingsService: any SettingsService,
        agentRegistry: AgentRegistry = DefaultAgentRegistry(),
        notificationCenter: NotificationCenter = .default,
        runNow: @escaping @MainActor (ScheduledTaskRunNowRequest) -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mutationService = mutationService
        self.providerDiscovery = providerDiscovery
        self.settingsService = settingsService
        self.agentRegistry = agentRegistry
        self.notificationCenter = notificationCenter
        runNowAction = runNow
        self.now = now

        reload()
        observeChanges()
    }

    deinit {
        changeObservationTask?.cancel()
    }

    func load() async {
        await refreshProviders()
        reload()
    }

    func reload() {
        do {
            let definitions = try modelContext.fetch(
                FetchDescriptor<ScheduledTask>(
                    sortBy: [SortDescriptor(\ScheduledTask.modifiedAt, order: .reverse)]
                )
            )
            tasks = definitions.map(makeRowPresentation)

            let fetchedProjects = try modelContext.fetch(
                FetchDescriptor<Project>(
                    sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.path)]
                )
            )
            projects = fetchedProjects.map { ScheduledTaskProjectOption(path: $0.path, name: $0.name) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(for filter: ScheduledTasksFilter) -> [ScheduledTaskRowPresentation] {
        switch filter {
        case .all:
            tasks
        case .active:
            tasks.filter { $0.state == .active }
        case .paused:
            tasks.filter { $0.state == .paused }
        }
    }

    func makeNewDraft() -> ScheduledTaskEditorDraft {
        let settings = settingsService.current
        let resolution = providerResolution
        let providerID = resolution.providerID ?? settings.defaultProvider
        let modelOptions = modelOptions(for: providerID)
        let storedModel = resolution.providerID == providerID ? resolution.storedThreadModel : nil
        let modelSelection = AgentModelOptionSelection.pickerValue(in: modelOptions, matching: storedModel)
        let effort = AgentModelOptionSelection.normalizedEffort(
            resolution.effort,
            options: modelOptions,
            selectedModel: storedModel
        )
        let permissionModes = permissionModeOptions(for: providerID)
        let permissionMode = permissionModes.contains(where: { $0.value == resolution.permissionMode })
            ? resolution.permissionMode
            : permissionModes.first?.value ?? settings.permissionMode
        let actionDate = now()
        let suggestedOccurrence = actionDate.addingTimeInterval(60 * 60)
        let calendar = Calendar.current

        return ScheduledTaskEditorDraft(
            id: UUID(),
            definitionID: nil,
            expectedRevision: nil,
            title: "",
            prompt: "",
            recurrenceKind: .daily,
            recurrenceAnchorAt: suggestedOccurrence,
            intervalMinutes: 60,
            wallClockHour: calendar.component(.hour, from: suggestedOccurrence),
            wallClockMinute: calendar.component(.minute, from: suggestedOccurrence),
            selectedWeekdays: Set(ScheduledTaskRecurrence.standardWeekdays),
            weeklyWeekday: calendar.component(.weekday, from: suggestedOccurrence),
            monthlyDay: calendar.component(.day, from: suggestedOccurrence),
            timeZoneIdentifier: TimeZone.current.identifier,
            providerID: providerID,
            modelSelection: modelSelection,
            effort: effort,
            permissionMode: permissionMode,
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            projectPath: nil,
            grantedRoots: []
        )
    }

    func requestCreate() {
        errorMessage = nil
        editorErrorMessage = nil
        pendingEditorDraft = makeNewDraft()
    }

    func requestEdit(definitionID: String) {
        pendingEditorDraft = makeEditDraft(definitionID: definitionID)
        if pendingEditorDraft != nil {
            errorMessage = nil
            editorErrorMessage = nil
        }
    }

    func dismissEditor() {
        pendingEditorDraft = nil
        editorErrorMessage = nil
    }

    func makeEditDraft(definitionID: String) -> ScheduledTaskEditorDraft? {
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            errorMessage = ScheduledTaskMutationError.definitionNotFound.localizedDescription
            reload()
            return nil
        }

        let recurrence = definition.recurrence
        let modelOptions = modelOptions(for: definition.providerID)
        return ScheduledTaskEditorDraft(
            id: UUID(),
            definitionID: definition.id,
            expectedRevision: definition.revision,
            title: definition.title,
            prompt: definition.prompt,
            recurrenceKind: recurrence?.kind ?? .once,
            recurrenceAnchorAt: definition.recurrenceAnchorAt ?? now().addingTimeInterval(60 * 60),
            intervalMinutes: definition.intervalMinutes ?? 60,
            wallClockHour: definition.wallClockHour ?? 9,
            wallClockMinute: definition.wallClockMinute ?? 0,
            selectedWeekdays: Set(recurrence?.selectedWeekdays ?? ScheduledTaskRecurrence.standardWeekdays),
            weeklyWeekday: definition.weeklyWeekday ?? 2,
            monthlyDay: definition.monthlyDay ?? 1,
            timeZoneIdentifier: definition.timeZoneIdentifier,
            providerID: definition.providerID,
            modelSelection: AgentModelOptionSelection.pickerValue(in: modelOptions, matching: definition.model),
            effort: definition.effort,
            permissionMode: definition.permissionMode,
            workspaceKind: definition.workspaceKind,
            workspaceStrategy: definition.workspaceStrategy,
            projectPath: definition.project?.path,
            grantedRoots: definition.grantedRoots
        )
    }

    @discardableResult
    func save(_ draft: ScheduledTaskEditorDraft) -> Bool {
        do {
            let edit = try makeDefinitionEdit(from: draft)
            if let definitionID = draft.definitionID {
                try mutationService.edit(
                    definitionID: definitionID,
                    expectedRevision: draft.expectedRevision,
                    edit: edit,
                    at: now()
                )
            } else {
                try mutationService.create(edit: edit, at: now())
            }
            editorErrorMessage = nil
            errorMessage = nil
            reload()
            return true
        } catch {
            editorErrorMessage = error.localizedDescription
            reload()
            return false
        }
    }

    func pause(_ task: ScheduledTaskRowPresentation) {
        performMutation {
            try mutationService.pause(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
        }
    }

    func resume(_ task: ScheduledTaskRowPresentation) {
        performMutation {
            try mutationService.resume(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
        }
    }

    func delete(_ task: ScheduledTaskRowPresentation) {
        performMutation {
            try mutationService.delete(definitionID: task.id, expectedRevision: task.revision)
        }
    }

    func runNow(_ task: ScheduledTaskRowPresentation) {
        do {
            let request = try mutationService.prepareRunNow(
                definitionID: task.id,
                expectedRevision: task.revision,
                at: now()
            )
            guard runNowAction(request) else {
                throw ScheduledTasksViewModelError.runNowRejected
            }
            errorMessage = nil
            pendingRunNowDefinitionIDs.insert(task.id)
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearEditorError() {
        editorErrorMessage = nil
    }
}

private extension ScheduledTasksViewModel {
    func observeChanges() {
        let notifications = notificationCenter.notifications(named: .scheduledTasksChanged)
        changeObservationTask = Task { @MainActor [weak self] in
            for await notification in notifications {
                guard !Task.isCancelled else {
                    return
                }
                if notification.userInfo?[ScheduledTasksChangeUserInfoKey.schedulerClaimResolved] as? Bool == true,
                   let definitionID = notification.userInfo?[ScheduledTasksChangeUserInfoKey.definitionID] as? String {
                    self?.pendingRunNowDefinitionIDs.remove(definitionID)
                }
                self?.reload()
            }
        }
    }

    func performMutation(_ mutation: () throws -> Void) {
        do {
            try mutation()
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }

    func makeDefinitionEdit(from draft: ScheduledTaskEditorDraft) throws -> ScheduledTaskDefinitionEdit {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ScheduledTasksViewModelError.titleRequired
        }
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw ScheduledTasksViewModelError.promptRequired
        }

        let project: Project?
        if draft.workspaceKind == .project {
            guard let projectPath = draft.projectPath else {
                throw ScheduledTasksViewModelError.projectRequired
            }
            guard let resolvedProject = resolveProject(path: projectPath) else {
                throw ScheduledTasksViewModelError.projectNotFound
            }
            project = resolvedProject
        } else {
            project = nil
        }

        let options = modelOptions(for: draft.providerID)
        let storedModel = AgentModelOptionSelection.storedModelValue(
            in: options,
            matching: draft.modelSelection
        )
        let normalizedModel = storedModel == AppSettings.defaultModelValue ? nil : storedModel
        let normalizedEffort = AgentModelOptionSelection.normalizedEffort(
            draft.effort,
            options: options,
            selectedModel: normalizedModel
        )

        return ScheduledTaskDefinitionEdit(
            title: title,
            prompt: prompt,
            recurrence: draft.recurrence,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            providerID: draft.providerID,
            model: normalizedModel,
            effort: normalizedEffort,
            permissionMode: draft.permissionMode,
            workspaceKind: draft.workspaceKind,
            workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: draft.grantedRoots,
            project: project
        )
    }

    func resolveProject(path: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        return try? modelContext.fetch(descriptor).first
    }

    func makeRowPresentation(_ definition: ScheduledTask) -> ScheduledTaskRowPresentation {
        let projectName = definition.project?.name
        let workspaceSummary: String
        switch definition.workspaceKind {
        case .privateWorkspace:
            let grantCount = definition.grantedRoots.count
            if grantCount == 0 {
                workspaceSummary = "Private workspace"
            } else {
                let grantLabel = grantCount == 1 ? "folder grant" : "folder grants"
                workspaceSummary = "Private workspace + \(grantCount) \(grantLabel)"
            }
        case .project:
            let strategy = definition.workspaceStrategy == .worktree ? "worktree" : "local checkout"
            workspaceSummary = "\(projectName ?? "Missing project") · \(strategy)"
        }

        return ScheduledTaskRowPresentation(
            id: definition.id,
            revision: definition.revision,
            title: definition.title,
            prompt: definition.prompt,
            state: definition.state,
            recurrence: definition.recurrence,
            timeZoneIdentifier: definition.timeZoneIdentifier,
            providerID: definition.providerID,
            workspaceSummary: workspaceSummary,
            nextOccurrenceAt: definition.nextOccurrenceAt,
            pauseReason: definition.pauseReason,
            lastError: definition.lastError,
            hasActiveRun: definition.runs.contains { !$0.hasKnownTerminalStatus },
            modifiedAt: definition.modifiedAt
        )
    }
}
