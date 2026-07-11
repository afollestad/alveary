import Foundation
import SwiftData

@MainActor
final class AppShotCaptureController {
    typealias PrepareCapture = @MainActor () async throws -> PreparedAppShotCapture
    typealias OpenDraft = @MainActor (PersistentIdentifier) async throws -> PersistentIdentifier
    typealias StageAppShot = @MainActor (ConversationState, AppShotAttachment) throws -> Void

    nonisolated static let noProjectMessage = "Add a project before capturing an app shot."

    private let appState: AppState
    private let modelContext: ModelContext
    private let settingsService: any SettingsService
    private let runtimeStore: any ConversationRuntimeStore
    private let attachmentStore: any ConversationAttachmentStore
    private let prepareCapture: PrepareCapture
    private let openDraft: OpenDraft
    private let stageAppShot: StageAppShot
    private let presentPermission: @MainActor (AppShotPermission) -> Void
    private let activateAlveary: @MainActor () -> Void
    private let playSuccessSound: @MainActor () -> Void
    private var activeCaptureTask: Task<Void, Never>?

    init(
        appState: AppState,
        modelContext: ModelContext,
        settingsService: any SettingsService,
        runtimeStore: any ConversationRuntimeStore,
        attachmentStore: any ConversationAttachmentStore,
        prepareCapture: @escaping PrepareCapture,
        openDraft: @escaping OpenDraft,
        stageAppShot: @escaping StageAppShot = { state, appShot in state.stageAppShot(appShot) },
        presentPermission: @escaping @MainActor (AppShotPermission) -> Void = { permission in
            AppShotPermissionDragGrantAssistant.shared.present(permission: permission, sourceFrameInScreen: nil)
        },
        activateAlveary: @escaping @MainActor () -> Void = AppShotCaptureFeedback.activateAlveary,
        playSuccessSound: @escaping @MainActor () -> Void = AppShotCaptureFeedback.playScreenshotSound
    ) {
        self.appState = appState
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.runtimeStore = runtimeStore
        self.attachmentStore = attachmentStore
        self.prepareCapture = prepareCapture
        self.openDraft = openDraft
        self.stageAppShot = stageAppShot
        self.presentPermission = presentPermission
        self.activateAlveary = activateAlveary
        self.playSuccessSound = playSuccessSound
    }

    @discardableResult
    func captureIfIdle() -> Task<Void, Never>? {
        guard activeCaptureTask == nil else {
            return nil
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { activeCaptureTask = nil }
            await capture()
        }
        activeCaptureTask = task
        return task
    }
}

private extension AppShotCaptureController {
    func capture() async {
        guard let intent = resolveIntent(),
              let preparedCapture = await resolvePreparedCapture() else {
            return
        }
        guard intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService) else {
            return
        }
        guard let claim = await resolveClaim(for: intent) else {
            return
        }
        guard intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService) else {
            return
        }
        guard await storeAndStage(preparedCapture, claim: claim) else {
            return
        }
        finishSuccessfulCapture(intent: intent, claim: claim)
    }

    func resolveIntent() -> AppShotDestinationIntent? {
        do {
            return try AppShotDestinationIntent.resolve(
                appState: appState,
                modelContext: modelContext,
                settingsService: settingsService
            )
        } catch AppShotRoutingError.noProject {
            activateAlveary()
            appState.presentUnexpectedError(message: Self.noProjectMessage)
            return nil
        } catch {
            presentAppLevelError(error)
            return nil
        }
    }

    func resolvePreparedCapture() async -> PreparedAppShotCapture? {
        do {
            return try await prepareCapture()
        } catch let error as AppShotCaptureError where error.missingPermission != nil {
            if let permission = error.missingPermission {
                presentPermission(permission)
            }
            return nil
        } catch {
            presentAppLevelError(error)
            return nil
        }
    }

    func resolveClaim(for intent: AppShotDestinationIntent) async -> AppShotDestinationClaim? {
        do {
            return try await claimDestination(for: intent)
        } catch {
            guard intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService) else {
                return nil
            }
            presentAppLevelError(error)
            return nil
        }
    }

    func storeAndStage(_ preparedCapture: PreparedAppShotCapture, claim: AppShotDestinationClaim) async -> Bool {
        let appShot: AppShotAttachment
        do {
            appShot = try await preparedCapture.store(
                in: attachmentStore,
                conversationId: claim.conversationID
            )
        } catch {
            presentStorageOrStagingError(error, claim: claim)
            return false
        }

        guard let state = resolvedState(for: claim) else {
            let error = await errorAfterRemovingStoredAttachment(
                appShot,
                originalError: AppShotRoutingError.destinationDeleted
            )
            presentStorageOrStagingError(error, claim: claim)
            return false
        }

        do {
            try stageAppShot(state, appShot)
            return true
        } catch {
            state.removeStagedAppShot(id: appShot.id)
            let reportedError = await errorAfterRemovingStoredAttachment(appShot, originalError: error)
            presentStorageOrStagingError(reportedError, claim: claim)
            return false
        }
    }

    func errorAfterRemovingStoredAttachment(
        _ appShot: AppShotAttachment,
        originalError: Error
    ) async -> Error {
        do {
            try await attachmentStore.removeAttachment(at: appShot.screenshot.fileURL)
            return originalError
        } catch {
            return AppShotAttachmentCleanupError(
                originalError: originalError.localizedDescription,
                cleanupError: error.localizedDescription
            )
        }
    }

    func claimDestination(for intent: AppShotDestinationIntent) async throws -> AppShotDestinationClaim {
        switch intent.route {
        case .conversation(let snapshot):
            return snapshot.claim(opensDraftOnSuccess: false)
        case .project(let projectID):
            let draftThreadID = try await openDraft(projectID)
            guard intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService),
                  let draft = modelContext.resolveThread(id: draftThreadID),
                  draft.isDraft,
                  draft.project?.persistentModelID == projectID,
                  let conversation = mainConversation(in: draft) else {
                throw AppShotRoutingError.draftUnavailable
            }
            return AppShotConversationSnapshot(thread: draft, conversation: conversation).claim(opensDraftOnSuccess: true)
        }
    }

    func resolvedState(for claim: AppShotDestinationClaim) -> ConversationState? {
        guard let conversation = modelContext.resolveConversation(id: claim.conversationPersistentID),
              conversation.id == claim.conversationID,
              conversation.thread?.persistentModelID == claim.threadID else {
            return nil
        }
        return runtimeStore.conversationState(for: claim.conversationID)
    }

    func finishSuccessfulCapture(intent: AppShotDestinationIntent, claim: AppShotDestinationClaim) {
        playSuccessSound()
        activateAlveary()

        if claim.opensDraftOnSuccess,
           intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService),
           let draft = modelContext.resolveThread(id: claim.threadID),
           draft.isDraft,
           modelContext.resolveConversation(id: claim.conversationPersistentID) != nil {
            appState.selectedConversationIDs[claim.threadID] = claim.conversationPersistentID
            appState.requestComposerFocus()
            appState.selectedSidebarItem = .thread(draft)
        } else if isClaimSelected(claim) {
            appState.requestComposerFocus()
        } else {
            appState.presentSuccessFeedback(message: "App shot added to \(claim.destinationName).")
        }
    }

    func presentStorageOrStagingError(_ error: Error, claim: AppShotDestinationClaim) {
        activateAlveary()
        if isClaimSelected(claim) {
            let state = runtimeStore.conversationState(for: claim.conversationID)
            if state.isViewMounted {
                state.lastTurnError = error.localizedDescription
                return
            }
        }
        appState.presentUnexpectedError(message: error.localizedDescription)
    }

    func presentAppLevelError(_ error: Error) {
        activateAlveary()
        appState.presentUnexpectedError(message: error.localizedDescription)
    }

    func isClaimSelected(_ claim: AppShotDestinationClaim) -> Bool {
        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              selectedThread.persistentModelID == claim.threadID,
              let thread = modelContext.resolveThread(id: claim.threadID),
              let selectedConversation = selectedConversation(
                  in: thread,
                  modelContext: modelContext,
                  appState: appState
              ) else {
            return false
        }
        return selectedConversation.persistentModelID == claim.conversationPersistentID
    }

    func mainConversation(in thread: AgentThread) -> Conversation? {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
            conversation.thread?.persistentModelID == threadID && conversation.isMain
        })
        return try? modelContext.fetch(descriptor).first
    }
}

private struct AppShotDestinationIntent {
    enum Route {
        case conversation(AppShotConversationSnapshot)
        case project(PersistentIdentifier)
    }

    let navigationToken: AppShotNavigationToken
    let route: Route

    @MainActor
    static func resolve(
        appState: AppState,
        modelContext: ModelContext,
        settingsService: any SettingsService
    ) throws -> AppShotDestinationIntent {
        let navigationToken = AppShotNavigationToken(appState: appState)
        if case .thread(let selectedThread) = appState.selectedSidebarItem {
            guard let thread = modelContext.resolveThread(id: selectedThread.persistentModelID),
                  thread.archivedAt == nil else {
                throw AppShotRoutingError.destinationUnavailable
            }
            let conversation: Conversation?
            if thread.isDraft {
                let threadID = thread.persistentModelID
                let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { candidate in
                    candidate.thread?.persistentModelID == threadID && candidate.isMain
                })
                conversation = try? modelContext.fetch(descriptor).first
            } else {
                conversation = selectedConversation(in: thread, modelContext: modelContext, appState: appState)
            }
            guard let conversation else {
                throw AppShotRoutingError.destinationUnavailable
            }
            return AppShotDestinationIntent(
                navigationToken: navigationToken,
                route: .conversation(AppShotConversationSnapshot(thread: thread, conversation: conversation))
            )
        }

        let resolution = NewThreadProjectResolver.resolve(
            selection: appState.selectedSidebarItem,
            previousSelection: appState.previousSelection,
            lastActiveProjectPath: settingsService.current.lastActiveProjectPath,
            modelContext: modelContext
        )
        settingsService.updateLastActiveProjectPath(resolution.lastActiveProjectPath)
        guard let project = resolution.project else {
            throw AppShotRoutingError.noProject
        }
        return AppShotDestinationIntent(
            navigationToken: navigationToken,
            route: .project(project.persistentModelID)
        )
    }

    @MainActor
    func isCurrent(
        appState: AppState,
        modelContext: ModelContext,
        settingsService: any SettingsService
    ) -> Bool {
        guard navigationToken == AppShotNavigationToken(appState: appState) else {
            return false
        }

        switch route {
        case .conversation(let snapshot):
            guard let thread = modelContext.resolveThread(id: snapshot.threadID),
                  thread.archivedAt == nil,
                  let conversation = modelContext.resolveConversation(id: snapshot.conversationPersistentID),
                  conversation.thread?.persistentModelID == snapshot.threadID else {
                return false
            }
            if thread.isDraft {
                return conversation.isMain && thread.project?.persistentModelID == snapshot.draftProjectID
            }
            return selectedConversation(in: thread, modelContext: modelContext, appState: appState)?.persistentModelID ==
                snapshot.conversationPersistentID
        case .project(let projectID):
            let resolution = NewThreadProjectResolver.resolve(
                selection: appState.selectedSidebarItem,
                previousSelection: appState.previousSelection,
                lastActiveProjectPath: settingsService.current.lastActiveProjectPath,
                modelContext: modelContext
            )
            return resolution.project?.persistentModelID == projectID
        }
    }
}

private struct AppShotConversationSnapshot {
    let threadID: PersistentIdentifier
    let conversationPersistentID: PersistentIdentifier
    let conversationID: String
    let draftProjectID: PersistentIdentifier?
    let destinationName: String

    @MainActor
    init(thread: AgentThread, conversation: Conversation) {
        threadID = thread.persistentModelID
        conversationPersistentID = conversation.persistentModelID
        conversationID = conversation.id
        draftProjectID = thread.isDraft ? thread.project?.persistentModelID : nil
        if thread.isDraft, let projectName = thread.project?.name {
            destinationName = "the new thread in \(projectName)"
        } else {
            destinationName = thread.displayName()
        }
    }

    func claim(opensDraftOnSuccess: Bool) -> AppShotDestinationClaim {
        AppShotDestinationClaim(
            threadID: threadID,
            conversationPersistentID: conversationPersistentID,
            conversationID: conversationID,
            destinationName: destinationName,
            opensDraftOnSuccess: opensDraftOnSuccess
        )
    }
}

private struct AppShotDestinationClaim {
    let threadID: PersistentIdentifier
    let conversationPersistentID: PersistentIdentifier
    let conversationID: String
    let destinationName: String
    let opensDraftOnSuccess: Bool
}

private enum AppShotNavigationToken: Equatable {
    case none
    case skills
    case mcp
    case project(PersistentIdentifier)
    // Effective conversation selection is checked in `isCurrent`; the raw selection cache may be repaired without changing destinations.
    case thread(PersistentIdentifier)
    case settings(previousSelection: AppState.SidebarBookmark?)

    @MainActor
    init(appState: AppState) {
        switch appState.selectedSidebarItem {
        case .skills:
            self = .skills
        case .mcp:
            self = .mcp
        case .project(let project):
            self = .project(project.persistentModelID)
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .settings:
            self = .settings(previousSelection: appState.previousSelection)
        case nil:
            self = .none
        }
    }
}

enum AppShotRoutingError: LocalizedError, Equatable {
    case noProject
    case destinationUnavailable
    case draftUnavailable
    case destinationDeleted

    var errorDescription: String? {
        switch self {
        case .noProject:
            return AppShotCaptureController.noProjectMessage
        case .destinationUnavailable:
            return "Could not resolve a conversation for the app shot."
        case .draftUnavailable:
            return "Could not create a new thread for the app shot."
        case .destinationDeleted:
            return "The app-shot destination was deleted before the capture finished."
        }
    }
}

struct AppShotAttachmentCleanupError: LocalizedError, Equatable {
    let originalError: String
    let cleanupError: String

    var errorDescription: String? {
        "\(originalError) Removing the stored app-shot screenshot also failed: \(cleanupError)"
    }
}
