@preconcurrency import AppKit
import Darwin
import SwiftData

extension AppDelegate {
    struct Dependencies: @unchecked Sendable {
        let agentsManager: any AgentsManager
        let providerDetection: any ProviderDetectionService
        /// Warmed at launch and dropped on wake, so the session's first thread creation does not
        /// pay for provider discovery and a slept machine does not answer from a stale probe.
        let providerDiscoveryCache: CachingAgentProviderDiscoveryService
        let sessionManager: any SessionManager
        let attachmentStore: any ConversationAttachmentStore
        let taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService
        let shellRunner: any ShellRunner
        let modelContainer: ModelContainer
        let flushConversationControllers: @MainActor () -> [ConversationControllerFlushFailure]
        let activateScheduledTasks: @MainActor () async -> Void
        let reconcileScheduledTasks: @MainActor () -> Void
        let teardownVoiceInput: @MainActor () -> Void
        let prepareScheduledTasksForTermination: @MainActor (Date) throws -> ScheduledTaskTerminationPreparation?
        let cleanupRuntimePreferences: @MainActor () -> Void
        let notificationRouter: NotificationRouter
        let settingsService: any SettingsService
        let menuBarController: MenuBarController
        let mainWindowPresenter: MainWindowPresenter
        let appShotCoordinator: AppShotCoordinator
        let workspaceNotificationCenter: NotificationCenter
        let notificationCenter: NotificationCenter
        let disableSuddenTermination: () -> Void
        let enableSuddenTermination: () -> Void
        let signalProcess: @Sendable (Int32, Int32) -> Int32
        let processExists: @Sendable (Int32) -> Bool
        let wakeRefreshDelay: Duration
        let shutdownPersistTimeout: TimeInterval
        let shutdownProcessGrace: TimeInterval
        let orphanCleanupGrace: TimeInterval

        @MainActor
        static func live() -> Dependencies {
            let component = AppDI.component
            return Dependencies(
                agentsManager: component.agentsManager,
                providerDetection: component.providerDetectionService,
                providerDiscoveryCache: component.cachedAgentProviderDiscoveryService,
                sessionManager: component.sessionManager,
                attachmentStore: component.conversationAttachmentStore,
                taskWorkspaceOwnershipService: component.taskWorkspaceOwnershipService,
                shellRunner: component.shellRunner,
                modelContainer: component.modelContainer,
                flushConversationControllers: {
                    component.conversationControllerRegistry.flushForTermination()
                },
                activateScheduledTasks: {
                    await component.scheduledTaskLifecycleCoordinator.activateAfterProviderRefresh()
                },
                reconcileScheduledTasks: {
                    component.scheduledTaskLifecycleCoordinator.reconcileAfterSystemChange()
                },
                teardownVoiceInput: {
                    component.voiceInputLifecycleController.teardownSynchronously()
                },
                prepareScheduledTasksForTermination: { actionDate in
                    try component.scheduledTaskLifecycleCoordinator.prepareForTermination(at: actionDate)
                },
                cleanupRuntimePreferences: {
                    AppRuntimeProfile.current.storageProfile.cleanupSettingsDefaults()
                },
                notificationRouter: component.notificationRouter,
                settingsService: component.settingsService,
                menuBarController: component.menuBarController,
                mainWindowPresenter: component.mainWindowPresenter,
                appShotCoordinator: component.appShotCoordinator,
                workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
                notificationCenter: .default,
                disableSuddenTermination: { ProcessInfo.processInfo.disableSuddenTermination() },
                enableSuddenTermination: { ProcessInfo.processInfo.enableSuddenTermination() },
                signalProcess: { pid, signal in Darwin.kill(pid, signal) },
                processExists: { pid in Self.defaultProcessExists(pid: pid) },
                wakeRefreshDelay: .seconds(2),
                shutdownPersistTimeout: 0.5,
                shutdownProcessGrace: 1.5,
                orphanCleanupGrace: 1.0
            )
        }

        private static func defaultProcessExists(pid: Int32) -> Bool {
            if Darwin.kill(pid, 0) == 0 {
                return true
            }

            return errno == EPERM
        }
    }
}
