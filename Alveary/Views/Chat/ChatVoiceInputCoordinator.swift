@preconcurrency import AppKit
import BlockInputKit
import Foundation
import Observation

@MainActor
@Observable
final class ChatVoiceInputCoordinator: VoiceInputComposerSink {
    nonisolated static let holdThreshold: Duration = .milliseconds(300)
    nonisolated static let recordingLimit: Duration = .seconds(600)
    nonisolated static let finalizationTimeout: Duration = .seconds(5)

    var phase: ChatVoiceInputPhase {
        didSet {
            if phase != oldValue {
                lifecycleController.composerSinkStateDidChange(self)
            }
        }
    }
    var notice: ChatVoiceInputNotice?
    var modelModalState: ChatVoiceInputModelModalState? {
        didSet {
            if modelModalState != oldValue {
                lifecycleController.composerSinkStateDidChange(self)
            }
        }
    }
    var latestNonemptyTranscript: String?

    let editorHandle = AppKitChatComposerEditorHandle()

    let service: any VoiceInputService
    let lifecycleController: VoiceInputLifecycleController
    let clock: any ChatVoiceInputClock
    let flushDraftFromEditor: () -> Void
    let supportedArchitecture: Bool
    let accessibilityAnnouncer: @MainActor (String) -> Void
    nonisolated let startupLifetime: ChatVoiceInputStartupLifetime

    var modelIsReady = false
    var recognitionSession: VoiceInputRecognitionSession?
    var provisionalSession: BlockInputProvisionalTextSession?
    var insertionContext: ComposerVoiceInsertionContext?
    var sessionGeneration: UInt64 = 0
    var acceptsPartialDelivery = false
    var activeSource: ChatVoiceInputActivationSource?
    var pressedAt: Duration?
    var isSourceHeld = false
    var isLatched = false
    var suppressedTrailingRelease: ChatVoiceInputActivationSource?
    var releaseBarrier = Set<ChatVoiceInputActivationSource>()
    var startupRelease: StartupRelease?
    var hasAttemptedStartupModelReload = false
    var preparationCancellationRequested = false
    var shouldAnnouncePreparationCancellation = false
    var pendingPreparationActivation: ChatVoiceInputPendingActivation?
    var isVoiceInputOwnedElsewhere = false
    var ownershipObserver: NSObjectProtocol?
    var composerContext: ChatVoiceInputComposerContext?
    var preparationGeneration: UInt64 = 0
    var preparationTask: Task<Void, Never>?
    var startupTask: Task<Void, Never>?
    var recordingLimitTask: Task<Void, Never>?
    var finalizationTimeoutTask: Task<Void, Never>?
    var pendingStartupRecognitionUpdates: [VoiceInputRecognitionUpdate] = []

    init(
        service: any VoiceInputService,
        lifecycleController: VoiceInputLifecycleController,
        clock: any ChatVoiceInputClock = ContinuousChatVoiceInputClock(),
        supportedArchitecture: Bool = ChatVoiceInputCoordinator.isSupportedArchitecture,
        accessibilityAnnouncer: @escaping @MainActor (String) -> Void = ChatVoiceInputCoordinator.postAccessibilityAnnouncement,
        flushDraftFromEditor: @escaping () -> Void
    ) {
        self.service = service
        startupLifetime = ChatVoiceInputStartupLifetime()
        self.lifecycleController = lifecycleController
        self.clock = clock
        self.supportedArchitecture = supportedArchitecture
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.flushDraftFromEditor = flushDraftFromEditor
        phase = supportedArchitecture ? .idle : .unavailable
        isVoiceInputOwnedElsewhere = lifecycleController.isVoiceInputOwned(byAnotherComposer: self)
        ownershipObserver = NotificationCenter.default.addObserver(
            forName: .voiceInputOwnershipChanged,
            object: lifecycleController,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshVoiceInputOwnership()
            }
        }
        editorHandle.onWillInvalidate = { [weak self] in
            self?.forceVoiceInputCommitSynchronously()
        }
        editorHandle.onDraftGenerationChange = { [weak self] in
            self?.invalidatePendingActivationIntent()
        }
    }

    isolated deinit {
        if let ownershipObserver {
            NotificationCenter.default.removeObserver(ownershipObserver)
        }
        preparationTask?.cancel()
        lifecycleController.clearActiveComposerSink(self)
        startupLifetime.invalidate()
    }

    var isDraftInteractionLocked: Bool {
        phase.locksDraftMutations
    }

    var isVoiceComposerInteractionLocked: Bool {
        modelModalState != nil || isDraftInteractionLocked
    }

    var isModelPreparationModalPresented: Bool {
        modelModalState != nil
    }

    var handlesEscape: Bool {
        provisionalSession != nil
    }

    var isButtonEnabled: Bool {
        guard supportedArchitecture else {
            return false
        }
        guard modelModalState == nil else {
            return false
        }
        guard !isVoiceInputOwnedElsewhere else {
            return false
        }
        switch phase {
        case .unavailable, .preparing, .starting, .finalizing, .cancelling, .cleanup:
            return false
        case .idle, .ready, .recording:
            return true
        }
    }

    var accessibilityLabel: String {
        switch phase {
        case .recording:
            "Stop Dictation"
        case .preparing:
            "Preparing Voice Input"
        case .starting:
            "Starting Dictation"
        case .finalizing:
            "Finalizing Dictation"
        case .cancelling:
            "Cancelling Dictation"
        case .cleanup:
            "Cleaning Up Voice Input"
        case .unavailable, .idle, .ready:
            "Start Dictation"
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func updateComposerContext(_ context: ChatVoiceInputComposerContext) {
        let changed = composerContext != nil && composerContext != context
        composerContext = context
        if changed {
            invalidatePendingActivationIntent()
        }
    }

    func invalidatePendingActivationIntent() {
        switch phase {
        case .preparing:
            pendingPreparationActivation = nil
            installReleaseBarrierForHeldSource()
        case .starting:
            beginPendingStartupCleanup()
        case .unavailable, .idle, .ready, .recording, .finalizing, .cancelling, .cleanup:
            break
        }
    }

    @discardableResult
    func physicalPress(_ source: ChatVoiceInputActivationSource) -> Bool {
        guard supportedArchitecture else {
            return false
        }
        guard modelModalState == nil else {
            return true
        }
        guard !isVoiceInputOwnedElsewhere else {
            present(message: Self.voiceInputOwnedElsewhereMessage, severity: .info)
            return true
        }
        if physicalPressIsSuppressed(for: source) {
            return true
        }
        if stopLatchedRecognition(from: source) {
            return true
        }
        if isSourceHeld {
            return true
        }
        return beginPhysicalPress(source)
    }

    private func physicalPressIsSuppressed(for source: ChatVoiceInputActivationSource) -> Bool {
        if !releaseBarrier.isEmpty || suppressedTrailingRelease != nil {
            return true
        }
        return activeSource != nil && activeSource != source
    }

    private func stopLatchedRecognition(from source: ChatVoiceInputActivationSource) -> Bool {
        guard isLatched, recognitionSession != nil else {
            return false
        }
        activeSource = source
        isSourceHeld = true
        suppressedTrailingRelease = source
        requestStopAndCommit()
        return true
    }

    private func beginPhysicalPress(_ source: ChatVoiceInputActivationSource) -> Bool {
        switch phase {
        case .idle, .ready:
            guard editorHandle.canStartVoiceInput else {
                return false
            }
            modelModalState = nil
            notice = nil
            hasAttemptedStartupModelReload = false
            activeSource = source
            isSourceHeld = true
            isLatched = false
            pressedAt = clock.now()
            startupRelease = nil
            activateReadyVoiceInputOrPrepare(activation: .physical(source))
            return true
        case .recording:
            return true
        case .unavailable, .preparing, .starting, .finalizing, .cancelling, .cleanup:
            return phase != .unavailable
        }
    }

    @discardableResult
    func physicalRelease(_ source: ChatVoiceInputActivationSource, forced: Bool = false) -> Bool {
        let removedReleaseBarrier = releaseBarrier.remove(source) != nil
        let removedSuppressedRelease = suppressedTrailingRelease == source
        if removedSuppressedRelease {
            suppressedTrailingRelease = nil
        }
        if removedReleaseBarrier || removedSuppressedRelease {
            if activeSource == source {
                clearPhysicalPress()
            }
            return true
        }
        guard activeSource == source else {
            return false
        }

        let duration = pressedAt.map { $0.duration(to: clock.now()) } ?? .zero
        isSourceHeld = false
        switch phase {
        case .preparing:
            releaseDuringPreparation(forced: forced)
        case .starting:
            startupRelease = StartupRelease(forced: forced, duration: duration)
            activeSource = nil
            pressedAt = nil
        case .recording:
            activeSource = nil
            pressedAt = nil
            if forced || duration >= Self.holdThreshold {
                requestStopAndCommit()
            } else {
                isLatched = true
            }
        case .finalizing, .cancelling, .cleanup:
            clearPhysicalPress()
        case .unavailable, .idle, .ready:
            clearPhysicalPress()
        }
        return true
    }

    private func releaseDuringPreparation(forced: Bool) {
        if forced {
            pendingPreparationActivation = nil
        }
        clearPhysicalPress()
    }

    func accessibilityToggle() {
        guard supportedArchitecture else {
            return
        }
        guard modelModalState == nil else {
            return
        }
        guard !isVoiceInputOwnedElsewhere else {
            present(message: Self.voiceInputOwnedElsewhereMessage, severity: .info)
            return
        }
        if recognitionSession != nil {
            installReleaseBarrierForHeldSource()
            requestStopAndCommit()
            return
        }
        guard releaseBarrier.isEmpty, suppressedTrailingRelease == nil else {
            return
        }
        guard editorHandle.canStartVoiceInput else {
            return
        }
        modelModalState = nil
        notice = nil
        hasAttemptedStartupModelReload = false
        startupRelease = nil
        activateReadyVoiceInputOrPrepare(activation: .accessibility)
    }

    @discardableResult
    func cancelFromEscape() -> Bool {
        guard let session = recognitionSession,
              let provisionalSession else {
            return false
        }
        installReleaseBarrierForHeldSource()
        advanceGeneration()
        phase = .cancelling
        service.cancelCaptureSynchronously(for: session)
        recordingLimitTask?.cancel()
        finalizationTimeoutTask?.cancel()
        let cancellationResult = editorHandle.finishProvisionalTextReplacement(
            provisionalSession,
            disposition: .cancel
        )
        self.provisionalSession = nil
        insertionContext = nil
        latestNonemptyTranscript = nil
        flushDraftFromEditor()
        phase = .cleanup
        if cancellationResult == .invalidated {
            presentDraftChangedNotice()
        } else {
            notice = ChatVoiceInputNotice(message: "Dictation cancelled.", severity: .info, recovery: nil)
            announce("Dictation cancelled")
        }

        let service = service
        startupTask = Task { [weak self] in
            await service.cancelRecognition(session)
            guard let self else { return }
            self.finishCleanup(session: session)
        }
        return true
    }

    func forceStopAndCommit(reason: String? = nil) {
        installReleaseBarrierForHeldSource()
        guard phase == .starting || recognitionSession != nil || provisionalSession != nil else {
            clearPendingGestureIntent()
            return
        }
        if let reason, phase == .starting || phase == .recording {
            notice = ChatVoiceInputNotice(message: reason, severity: .warning, recovery: nil)
            announce(reason)
        }
        if beginForcedPendingStartupCleanup() {
            return
        }
        requestStopAndCommit()
    }

    func forceVoiceInputCommitSynchronously() {
        cancelModelPreparationForTeardown()
        if beginForcedPendingStartupCleanup() {
            return
        }
        guard recognitionSession != nil || provisionalSession != nil else {
            clearPendingGestureIntent()
            return
        }
        installReleaseBarrierForHeldSource()
        advanceGeneration()
        preparationTask?.cancel()
        startupTask?.cancel()
        recordingLimitTask?.cancel()
        finalizationTimeoutTask?.cancel()
        if let session = recognitionSession {
            service.shutdownCaptureSynchronously(for: session)
        }
        let draftFinishOutcome = finishProvisionalSynchronously(
            preferredTranscript: latestNonemptyTranscript
        )
        if draftFinishOutcome == .invalidated {
            presentDraftChangedNotice()
        }
        insertionContext = nil
        latestNonemptyTranscript = nil

        guard let session = recognitionSession else {
            phase = modelIsReady ? .ready : .idle
            lifecycleController.clearActiveComposerSink(self)
            return
        }

        phase = .cleanup
        let service = service
        startupTask = Task { [weak self] in
            _ = await service.stopRecognition(session)
            guard let self else { return }
            self.finishCleanup(session: session)
        }
    }

    func composerDidDisappear() {
        cancelModelPreparationForTeardown()
        forceVoiceInputCommitSynchronously()
    }
}

final class ChatVoiceInputStartupLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var activeAttempt: VoiceInputRecognitionAttempt?

    func begin(_ attempt: VoiceInputRecognitionAttempt) {
        lock.withLock {
            activeAttempt = attempt
        }
    }

    func finish(_ attempt: VoiceInputRecognitionAttempt) {
        let shouldFinish = lock.withLock { () -> Bool in
            guard activeAttempt === attempt else { return false }
            activeAttempt = nil
            return true
        }
        if shouldFinish {
            attempt.finish()
        }
    }

    func invalidate() {
        let attempt = lock.withLock { () -> VoiceInputRecognitionAttempt? in
            defer { activeAttempt = nil }
            return activeAttempt
        }
        attempt?.cancelSynchronously()
    }
}
