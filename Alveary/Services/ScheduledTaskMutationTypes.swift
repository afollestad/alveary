import Foundation

extension Notification.Name {
    static let scheduledTasksChanged = Notification.Name("scheduledTasksChanged")
}

enum ScheduledTasksChangeUserInfoKey {
    static let definitionID = "definitionID"
    static let schedulerClaimResolved = "schedulerClaimResolved"
    static let schedulerClaimErrorMessage = "schedulerClaimErrorMessage"
}

extension NotificationCenter {
    func postScheduledTasksChanged(
        object: Any? = nil,
        definitionID: String? = nil,
        schedulerClaimResolved: Bool = false,
        schedulerClaimErrorMessage: String? = nil
    ) {
        var userInfo: [AnyHashable: Any] = [:]
        if let definitionID {
            userInfo[ScheduledTasksChangeUserInfoKey.definitionID] = definitionID
        }
        if schedulerClaimResolved {
            userInfo[ScheduledTasksChangeUserInfoKey.schedulerClaimResolved] = true
        }
        if let schedulerClaimErrorMessage {
            userInfo[ScheduledTasksChangeUserInfoKey.schedulerClaimErrorMessage] = schedulerClaimErrorMessage
        }
        post(
            name: .scheduledTasksChanged,
            object: object,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}

struct ScheduledTaskDefinitionEdit {
    let title: String
    let prompt: String
    let destination: ScheduledTaskDestination
    let recurrence: ScheduledTaskRecurrence
    let timeZoneIdentifier: String
    let providerID: String
    let model: String?
    let effort: String
    let permissionMode: String
    let workspaceKind: ScheduledTaskWorkspaceKind
    let workspaceStrategy: ScheduledTaskWorkspaceStrategy
    let grantedRoots: [String]
    let project: Project?
    let targetThread: AgentThread?

    init(
        title: String,
        prompt: String,
        destination: ScheduledTaskDestination = .newThread,
        recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String,
        providerID: String,
        model: String?,
        effort: String,
        permissionMode: String,
        workspaceKind: ScheduledTaskWorkspaceKind,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy,
        grantedRoots: [String],
        project: Project?,
        targetThread: AgentThread? = nil
    ) {
        self.title = title
        self.prompt = prompt
        self.destination = destination
        self.recurrence = recurrence
        self.timeZoneIdentifier = timeZoneIdentifier
        self.providerID = providerID
        self.model = model
        self.effort = effort
        self.permissionMode = permissionMode
        self.workspaceKind = workspaceKind
        self.workspaceStrategy = workspaceStrategy
        self.grantedRoots = grantedRoots
        self.project = project
        self.targetThread = targetThread
    }
}

enum ScheduledTaskMutationError: Error, Equatable, LocalizedError {
    case definitionNotFound
    case proposalNotFound
    case invalidRecurrence
    case invalidDestination
    case projectWorkspaceRequiresProject
    case existingThreadRequiresPinnedThread
    case workspaceRootsChanged
    case revisionConflict(expected: Int, actual: Int)
    case runNowBlockedByActiveRun
    case runNowBlockedByTargetWait
    case scheduleIsCompleted
    case scheduleIsNotPaused

    var errorDescription: String? {
        switch self {
        case .definitionNotFound:
            "Scheduled task no longer exists."
        case .proposalNotFound:
            "Scheduling proposal no longer exists."
        case .invalidRecurrence:
            "Scheduled task recurrence is invalid."
        case .invalidDestination:
            "Scheduled task destination is invalid."
        case .projectWorkspaceRequiresProject:
            "Project schedules require a project."
        case .existingThreadRequiresPinnedThread:
            "Existing-thread schedules require an available pinned thread."
        case .workspaceRootsChanged:
            "The selected project or folder grants changed and must be reviewed before saving."
        case let .revisionConflict(expected, actual):
            "Scheduled task changed from revision \(expected) to \(actual)."
        case .runNowBlockedByActiveRun:
            "Scheduled task is already running or waiting for input."
        case .runNowBlockedByTargetWait:
            "Scheduled task is waiting for its attached thread to become idle."
        case .scheduleIsCompleted:
            "Completed one-time scheduled tasks cannot be paused."
        case .scheduleIsNotPaused:
            "Only a paused scheduled task can be resumed."
        }
    }
}
