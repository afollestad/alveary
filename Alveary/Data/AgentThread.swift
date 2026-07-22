import Foundation
import SwiftData

@Model
final class AgentThread {
    var name: String
    var hasCustomName: Bool
    var branch: String?
    var pendingCleanupBranches: [String]
    var worktreePath: String?
    var hasCompletedInitialSetup: Bool
    var permissionMode: String
    var planModeEnabled: Bool?
    var effort: String
    var model: String?
    var speedMode: String?
    var useWorktree: Bool
    var isPinned: Bool = false
    var pinnedSortOrder: Int?
    var isDraft: Bool = false
    var isForkBootstrapPending: Bool = false
    var modifiedAt: Date?
    var archivedAt: Date?
    var modeRawValue: String = AgentThreadMode.project.rawValue
    var taskPrimaryRoot: String?
    var taskGrantedRoots: [String] = []
    var taskWorkspaceOwnershipStrategyRawValue: String?
    var taskWorkspaceMarkerID: String?
    var taskSourceProjectPath: String?
    var project: Project?
    var scheduledTaskRun: ScheduledTaskRun?
    @Relationship(deleteRule: .nullify, inverse: \ScheduledTask.targetThread)
    var targetedScheduledTasks: [ScheduledTask] = []
    @Relationship(deleteRule: .nullify, inverse: \ScheduledTaskRun.targetThread)
    var targetedScheduledTaskRuns: [ScheduledTaskRun] = []
    @Relationship(deleteRule: .cascade, inverse: \Conversation.thread) var conversations: [Conversation]

    init(
        name: String,
        hasCustomName: Bool = false,
        branch: String? = nil,
        pendingCleanupBranches: [String] = [],
        worktreePath: String? = nil,
        hasCompletedInitialSetup: Bool = false,
        permissionMode: String = "default",
        planModeEnabled: Bool = false,
        effort: String = AppSettings.defaultEffortLevel,
        model: String? = nil,
        speedMode: String? = AgentSpeedMode.standard.rawValue,
        useWorktree: Bool = false,
        isPinned: Bool = false,
        pinnedSortOrder: Int? = nil,
        isDraft: Bool = false,
        isForkBootstrapPending: Bool = false,
        modifiedAt: Date? = nil,
        archivedAt: Date? = nil,
        mode: AgentThreadMode = .project,
        taskWorkspaceDescriptor: TaskWorkspaceDescriptor? = nil,
        project: Project? = nil,
        scheduledTaskRun: ScheduledTaskRun? = nil,
        conversations: [Conversation] = []
    ) {
        self.name = name
        self.hasCustomName = hasCustomName
        self.branch = branch
        self.pendingCleanupBranches = pendingCleanupBranches
        self.worktreePath = worktreePath.map(CanonicalPath.normalize)
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.permissionMode = permissionMode
        self.planModeEnabled = planModeEnabled
        self.effort = effort
        self.model = model
        self.speedMode = speedMode
        self.useWorktree = useWorktree
        self.isPinned = isPinned
        self.pinnedSortOrder = pinnedSortOrder
        self.isDraft = isDraft
        self.isForkBootstrapPending = isForkBootstrapPending
        self.modifiedAt = modifiedAt
        self.archivedAt = archivedAt
        self.modeRawValue = mode.rawValue
        self.taskPrimaryRoot = taskWorkspaceDescriptor?.primaryRoot
        self.taskGrantedRoots = taskWorkspaceDescriptor?.grantedRoots ?? []
        self.taskWorkspaceOwnershipStrategyRawValue = taskWorkspaceDescriptor?.ownershipStrategy.rawValue
        self.taskWorkspaceMarkerID = taskWorkspaceDescriptor?.ownershipMarkerID
        self.taskSourceProjectPath = taskWorkspaceDescriptor?.sourceProjectPath
        self.project = project
        self.scheduledTaskRun = scheduledTaskRun
        self.conversations = conversations
    }
}

enum ThreadDraftNotificationKey {
    static let threadID = "threadID"
    static let conversationID = "conversationID"
    static let projectPath = "projectPath"
    static let mode = "mode"
}

enum ThreadLifecycleNotificationKey {
    static let threadID = "threadID"
    static let mode = "mode"
}

extension Notification.Name {
    static let threadDraftMaterialized = Notification.Name("threadDraftMaterialized")
    static let threadDraftProjectChanged = Notification.Name("threadDraftProjectChanged")
    static let threadLifecycleChanged = Notification.Name("threadLifecycleChanged")
    static let threadPresentationChanged = Notification.Name("threadPresentationChanged")
}

extension AgentThread {
    var blockingScheduledTaskAttachment: ScheduledTask? {
        targetedScheduledTasks.min {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id < $1.id
        }
    }

    var hasBlockingScheduledTaskRunAttachment: Bool {
        targetedScheduledTaskRuns.contains {
            !$0.hasKnownTerminalStatus || $0.requiresFinalizationRecovery
        }
    }

    var hasPendingScheduledTaskWorktreeCleanup: Bool {
        scheduledTaskRun?.hasPendingWorktreeCleanupMetadata == true
    }

    var mode: AgentThreadMode {
        get { AgentThreadMode(rawValue: modeRawValue) ?? .project }
        set { modeRawValue = newValue.rawValue }
    }

    var effectiveMode: AgentThreadMode {
        if let persistedMode = AgentThreadMode(rawValue: modeRawValue) {
            return persistedMode
        }
        guard let scheduledTaskRun else {
            return .project
        }
        return scheduledTaskRun.workspaceKindSnapshot == .privateWorkspace ? .task : .project
    }

    var taskWorkspaceDescriptor: TaskWorkspaceDescriptor? {
        get {
            guard mode == .task,
                  let taskPrimaryRoot,
                  !taskPrimaryRoot.isEmpty,
                  let strategyRawValue = taskWorkspaceOwnershipStrategyRawValue,
                  let ownershipStrategy = TaskWorkspaceOwnershipStrategy(rawValue: strategyRawValue)
            else {
                return nil
            }

            return TaskWorkspaceDescriptor(
                persistedPrimaryRoot: taskPrimaryRoot,
                persistedGrantedRoots: taskGrantedRoots,
                ownershipStrategy: ownershipStrategy,
                ownershipMarkerID: taskWorkspaceMarkerID,
                persistedSourceProjectPath: taskSourceProjectPath
            )
        }
        set {
            taskPrimaryRoot = newValue?.primaryRoot
            taskGrantedRoots = newValue?.grantedRoots ?? []
            taskWorkspaceOwnershipStrategyRawValue = newValue?.ownershipStrategy.rawValue
            taskWorkspaceMarkerID = newValue?.ownershipMarkerID
            taskSourceProjectPath = newValue?.sourceProjectPath
        }
    }

    var primaryWorkingDirectory: String? {
        switch effectiveMode {
        case .project:
            worktreePath ?? project?.path
        case .task:
            taskWorkspaceDescriptor?.primaryRoot
        }
    }

    var sourceProjectCleanupPath: String? {
        switch effectiveMode {
        case .project:
            project?.path
        case .task:
            taskWorkspaceDescriptor?.sourceProjectPath
        }
    }

    var normalizedSpeedMode: AgentSpeedMode {
        AgentSpeedMode(normalizing: speedMode)
    }

    func prepareForRestore() {
        for conversation in conversations {
            conversation.refreshPendingRestoreContextFromHistory()
        }
        isPinned = false
        pinnedSortOrder = nil
        archivedAt = nil
    }
}
