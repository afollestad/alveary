import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
struct ScheduledTaskRecoveryFixture {
    let container: ModelContainer
    let context: ModelContext
    let coordinator: ScheduledTaskRunRecoveryCoordinator
    let controllerRegistry: RecordingRecoveryControllerRegistry
    let notificationManager: RecordingNotificationManager
    let workspaceOwnershipService: RecoveryWorkspaceOwnershipService

    init(
        saveChanges: @escaping ScheduledTaskRunRecoveryCoordinator.StateSaver = { try $0.save() }
    ) throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let controllerRegistry = RecordingRecoveryControllerRegistry()
        let notificationManager = RecordingNotificationManager()
        let workspaceOwnershipService = RecoveryWorkspaceOwnershipService()
        self.container = container
        self.context = context
        self.controllerRegistry = controllerRegistry
        self.notificationManager = notificationManager
        self.workspaceOwnershipService = workspaceOwnershipService
        self.coordinator = ScheduledTaskRunRecoveryCoordinator(
            modelContext: context,
            controllerRegistry: controllerRegistry,
            notificationManager: notificationManager,
            workspaceOwnershipService: workspaceOwnershipService,
            noteFormatter: ScheduledTaskOccurrenceNoteFormatter(
                locale: Locale(identifier: "en_US_POSIX")
            ),
            saveChanges: saveChanges
        )
    }

    func insertRun(
        status: ScheduledTaskRunStatus,
        occurrenceAt: Date,
        withPendingApproval: Bool = false,
        withThread: Bool = true
    ) -> ScheduledTaskRun {
        let run = makeRecoveryScheduledTaskRun(status: status, occurrenceAt: occurrenceAt)
        guard withThread else {
            context.insert(run)
            run.workspaceSnapshot = WorkspaceSnapshot(
            primarySource: run.projectPathSnapshot.map { SourceFolderSnapshot(path: $0) },
            grants: run.grantedRootsSnapshot.map { SourceFolderSnapshot(path: $0) }
        )
        return run
        }
        let thread = AgentThread(name: "Recovered scheduled task", mode: .task, scheduledTaskRun: run)
        let conversation = Conversation(isMain: true, thread: thread)
        thread.conversations = [conversation]
        run.thread = thread
        if withPendingApproval {
            let prompt = ConversationEventRecord(
                conversationId: conversation.id,
                type: "tool_call",
                toolId: "approval-1",
                toolName: "AskUserQuestion",
                toolInput: #"{"questions":[{"question":"Continue?","header":"Continue","options":[],"multiSelect":false}]}"#,
                conversation: conversation
            )
            let approval = ConversationEventRecord(
                conversationId: conversation.id,
                type: "tool_approval",
                toolId: "approval-1",
                toolName: "AskUserQuestion",
                conversation: conversation
            )
            conversation.events = [prompt, approval]
            context.insert(prompt)
            context.insert(approval)
        }
        context.insert(run)
        context.insert(thread)
        context.insert(conversation)
        run.workspaceSnapshot = WorkspaceSnapshot(
            primarySource: run.projectPathSnapshot.map { SourceFolderSnapshot(path: $0) },
            grants: run.grantedRootsSnapshot.map { SourceFolderSnapshot(path: $0) }
        )
        return run
    }
}

final class RecoveryWorkspaceOwnershipService: TaskWorkspaceOwnershipService, @unchecked Sendable {
    private var allowedDescriptors: [TaskWorkspaceDescriptor] = []
    private var directoryIdentities: [String: TaskWorkspaceFileSystemIdentity] = [:]
    private var sourceProjectIdentities: [String: TaskWorkspaceFileSystemIdentity] = [:]

    func allow(
        _ descriptor: TaskWorkspaceDescriptor,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity? = nil
    ) {
        allowedDescriptors.append(descriptor)
        if let markerID = descriptor.ownershipMarkerID,
           let sourceProjectIdentity {
            sourceProjectIdentities[markerID] = sourceProjectIdentity
        }
    }

    func setIdentity(_ identity: TaskWorkspaceFileSystemIdentity, at path: String) {
        directoryIdentities[path] = identity
    }

    func createPrivateWorkspace() throws -> TaskWorkspaceDescriptor {
        throw TaskWorkspaceOwnershipError.workspaceNotOwned
    }

    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String]
    ) throws -> TaskWorkspaceDescriptor {
        throw TaskWorkspaceOwnershipError.workspaceNotOwned
    }

    func canonicalizeGrants(_ paths: [String], excludingPrimaryRoot primaryRoot: String?) throws -> [String] {
        paths.map(CanonicalPath.normalize)
    }

    func directoryIdentity(at path: String) throws -> TaskWorkspaceFileSystemIdentity {
        guard let identity = directoryIdentities[path] else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
        return identity
    }

    func sourceProjectIdentity(
        forOwnedWorktree descriptor: TaskWorkspaceDescriptor
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        guard let markerID = descriptor.ownershipMarkerID else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
        return sourceProjectIdentities[markerID]
    }

    func ownedWorktreeIdentity(
        for descriptor: TaskWorkspaceDescriptor
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        directoryIdentities[descriptor.primaryRoot]
    }

    func validateOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        guard allowedDescriptors.contains(descriptor) else {
            throw TaskWorkspaceOwnershipError.workspaceNotOwned
        }
    }

    func validateOwnedWorkspaceForRemoval(_ descriptor: TaskWorkspaceDescriptor) throws {
        try validateOwnedWorkspace(descriptor)
    }

    func discardOwnedWorktreeRecord(_ descriptor: TaskWorkspaceDescriptor) throws {
        throw TaskWorkspaceOwnershipError.workspaceNotOwned
    }

    func removeOwnedWorkspace(_ descriptor: TaskWorkspaceDescriptor) throws {
        throw TaskWorkspaceOwnershipError.workspaceNotOwned
    }

    func removeOrphanedPrivateWorkspaces(retainingMarkerIDs: Set<String>) throws {}
}
@MainActor
func makeRecoveryScheduledTaskRun(
    status: ScheduledTaskRunStatus,
    occurrenceAt: Date
) -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition-\(UUID().uuidString)",
        definitionRevision: 1,
        occurrenceAt: occurrenceAt,
        triggerKind: .scheduled,
        status: status,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        destinationSnapshot: .newThreadPerRun,
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "claude",
        effortSnapshot: "medium",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .privateWorkspace,
        workspaceStrategySnapshot: .worktree,
        workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot(projectRoot: nil, grantedRoots: [])
    )
}
