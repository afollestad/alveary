import AgentCLIKit
import Foundation
import SwiftData

@MainActor
final class AppShotCaptureController {
    typealias PrepareCapture = @MainActor () async throws -> PreparedAppShotCapture
    typealias OpenDraft = @MainActor (PersistentIdentifier?) async throws -> PersistentIdentifier
    typealias StageAppShot = @MainActor (ConversationState, AppShotAttachment) throws -> Void
    typealias IsVoiceInputLocked = @MainActor () -> Bool

    private let appState: AppState
    private let modelContext: ModelContext
    private let settingsService: any SettingsService
    private let runtimeStore: any ConversationRuntimeStore
    private let attachmentStore: any ConversationAttachmentStore
    private let harnessDiscovery: (any AgentHarnessDiscoveryService)?
    private let isVoiceInputLocked: IsVoiceInputLocked
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
        harnessDiscovery: (any AgentHarnessDiscoveryService)? = nil,
        isVoiceInputLocked: @escaping IsVoiceInputLocked = { false },
        prepareCapture: @escaping PrepareCapture,
        openDraft: @escaping OpenDraft,
        stageAppShot: @escaping StageAppShot = { state, appShot in state.stageAppShot(appShot) },
        presentPermission: @escaping @MainActor (AppShotPermission) -> Void = { permission in
            AppShotPermissionDragGrantAssistant.shared.present(permission: permission, sourceFrameInScreen: nil)
        },
        activateAlveary: @escaping @MainActor () -> Void,
        playSuccessSound: @escaping @MainActor () -> Void = AppShotCaptureFeedback.playScreenshotSound
    ) {
        self.appState = appState
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.runtimeStore = runtimeStore
        self.attachmentStore = attachmentStore
        self.harnessDiscovery = harnessDiscovery
        self.isVoiceInputLocked = isVoiceInputLocked
        self.prepareCapture = prepareCapture
        self.openDraft = openDraft
        self.stageAppShot = stageAppShot
        self.presentPermission = presentPermission
        self.activateAlveary = activateAlveary
        self.playSuccessSound = playSuccessSound
    }

    @discardableResult
    func captureIfIdle() -> Task<Void, Never>? {
        guard activeCaptureTask == nil,
              !isVoiceInputLocked() else {
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
        guard !isVoiceInputLocked(),
              let intent = resolveIntent() else {
            return
        }
        do {
            let destinationID: PersistentIdentifier?
            let draftProjectID: PersistentIdentifier?
            switch intent.route {
            case .conversation(let snapshot):
                destinationID = snapshot.conversationPersistentID
                draftProjectID = nil
            case .draft(let projectID):
                destinationID = nil
                draftProjectID = projectID
            }
            try await validateCaptureModel(conversationID: destinationID, draftProjectID: draftProjectID)
        } catch {
            presentAppLevelError(error)
            return
        }
        guard !isVoiceInputLocked(),
              intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService),
              let preparedCapture = await resolvePreparedCapture() else { return }
        guard !isVoiceInputLocked(),
              intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService) else {
            return
        }
        guard let claim = await resolveClaim(for: intent) else {
            return
        }
        do {
            try await validateCaptureModel(conversationID: claim.conversationPersistentID)
        } catch {
            presentAppLevelError(error)
            return
        }
        guard !isVoiceInputLocked(),
              intent.isCurrent(appState: appState, modelContext: modelContext, settingsService: settingsService) else {
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

        guard !isVoiceInputLocked() else {
            await removeStoredAttachmentSuppressedByVoiceInput(appShot, claim: claim)
            return false
        }

        do {
            try await validateCaptureModel(conversationID: claim.conversationPersistentID)
            guard !isVoiceInputLocked() else {
                await removeStoredAttachmentSuppressedByVoiceInput(appShot, claim: claim)
                return false
            }
            try stageStoredAppShot(appShot, claim: claim)
            return true
        } catch {
            let reportedError = await errorAfterRemovingStoredAttachment(appShot, originalError: error)
            presentStorageOrStagingError(reportedError, claim: claim)
            return false
        }
    }

    /// Setup cancellation can replace composer state during discovery; resolve the claim after the final await.
    func stageStoredAppShot(_ appShot: AppShotAttachment, claim: AppShotDestinationClaim) throws {
        guard let state = resolvedState(for: claim) else {
            throw AppShotRoutingError.destinationDeleted
        }
        do {
            try stageAppShot(state, appShot)
        } catch {
            state.removeStagedAppShot(id: appShot.id)
            throw error
        }
    }

    func removeStoredAttachmentSuppressedByVoiceInput(
        _ appShot: AppShotAttachment,
        claim: AppShotDestinationClaim
    ) async {
        do {
            try await attachmentStore.removeAttachment(at: appShot.screenshot.fileURL)
        } catch {
            presentStorageOrStagingError(
                AppShotAttachmentCleanupError(
                    originalError: "Voice input became active before the app shot could be attached.",
                    cleanupError: error.localizedDescription
                ),
                claim: claim
            )
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
        case .draft(let projectID):
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

    /// Keyboard capture shares the model gate with the composer, including changes while capture or storage is suspended.
    func validateCaptureModel(conversationID: PersistentIdentifier?, draftProjectID: PersistentIdentifier? = nil) async throws {
        let selection = try captureModelSelection(conversationID: conversationID, draftProjectID: draftProjectID)
        guard AppShotHarnessStrategy(harnessID: selection.harness) != nil else {
            throw AppShotCaptureError.unsupportedHarness(selection.harness)
        }
        guard selection.harness == "opencode" else { return }
        let projectURL = selection.directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let status = await harnessDiscovery?.harnessStatuses(projectURL: projectURL)[.opencode]
        let current = try captureModelSelection(conversationID: conversationID, draftProjectID: draftProjectID)
        guard selection == current else { throw AppShotRoutingError.destinationUnavailable }
        try HarnessRequestValidation.validateOpenCodeModel(model: selection.model, effort: nil, hasImages: true, status: status)
    }

    func captureModelSelection(
        conversationID: PersistentIdentifier?, draftProjectID: PersistentIdentifier?
    ) throws -> AppShotCaptureModelSelection {
        guard let conversationID else {
            let directory: String?
            if let draftProjectID, let current = modelContext.resolveProject(id: draftProjectID) {
                directory = current.path
            } else {
                directory = nil
            }
            return AppShotCaptureModelSelection(
                harness: settingsService.current.defaultHarness, model: settingsService.current.defaultModel, directory: directory
            )
        }
        guard let conversation = modelContext.resolveConversation(id: conversationID) else {
            throw AppShotRoutingError.destinationDeleted
        }
        return AppShotCaptureModelSelection(
            harness: conversation.harness ?? conversation.harnessSessionHarnessId ?? settingsService.current.defaultHarness,
            model: conversation.thread?.model,
            directory: conversation.thread?.primaryWorkingDirectory
        )
    }
}

private struct AppShotCaptureModelSelection: Equatable {
    let harness: String
    let model: String?
    let directory: String?
}
