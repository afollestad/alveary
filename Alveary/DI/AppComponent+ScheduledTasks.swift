import NeedleFoundation

@MainActor
extension AppComponent {
    var scheduledTaskPreflightValidator: DefaultScheduledTaskPreflightValidator {
        return shared {
            DefaultScheduledTaskPreflightValidator(
                providerDiscovery: agentCLIKitProviderDiscoveryService,
                workspaceOwnershipService: taskWorkspaceOwnershipService,
                worktreeManager: worktreeManager
            )
        }
    }

    var scheduledTaskSchedulerEngine: ScheduledTaskSchedulerEngine {
        return shared {
            ScheduledTaskSchedulerEngine(
                modelContext: modelContainer.mainContext,
                preflightValidator: scheduledTaskPreflightValidator.validate
            )
        }
    }

    var scheduledTaskRootLock: ScheduledTaskRootLock {
        return shared { ScheduledTaskRootLock() }
    }

    var scheduledTaskRunMaterializer: any ScheduledTaskRunMaterializing {
        return shared {
            let failureNotifier = ScheduledTaskFailureNotifier(notificationManager: notificationManager)
            return DefaultScheduledTaskRunMaterializer(
                modelContext: modelContainer.mainContext,
                worktreeManager: worktreeManager,
                workspaceOwnershipService: taskWorkspaceOwnershipService,
                failureNotification: { message, conversationID in
                    failureNotifier.publish(message: message, conversationID: conversationID)
                }
            )
        }
    }

    var scheduledTaskRunExecutor: any ScheduledTaskRunExecuting {
        return shared {
            DefaultScheduledTaskRunExecutor(
                modelContext: modelContainer.mainContext,
                controllerRegistry: conversationControllerRegistry,
                notificationManager: notificationManager
            )
        }
    }

    var scheduledTaskRunRecoveryCoordinator: ScheduledTaskRunRecoveryCoordinator {
        return shared {
            ScheduledTaskRunRecoveryCoordinator(
                modelContext: modelContainer.mainContext,
                controllerRegistry: conversationControllerRegistry,
                notificationManager: notificationManager,
                workspaceOwnershipService: taskWorkspaceOwnershipService
            )
        }
    }

    var scheduledTaskSchedulerCoordinator: ScheduledTaskSchedulerCoordinator {
        return shared {
            ScheduledTaskSchedulerCoordinator(
                modelContext: modelContainer.mainContext,
                engine: scheduledTaskSchedulerEngine,
                rootLock: scheduledTaskRootLock,
                materializer: scheduledTaskRunMaterializer,
                executor: scheduledTaskRunExecutor,
                keepAwakeService: keepAwakeService,
                notificationManager: notificationManager,
                terminalConversationReconciliation: { conversationID in
                    self.conversationControllerRegistry.reconcileScheduledTaskTerminalState(
                        conversationID: conversationID
                    )
                }
            )
        }
    }
}
