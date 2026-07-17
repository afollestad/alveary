import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func makeFixture(
        text: String = "Draft",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ChatVoiceInputTestFixture {
        let service = FakeChatVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: service)
        return try makeFixture(
            text: text,
            service: service,
            lifecycleController: lifecycleController,
            file: file,
            line: line
        )
    }

    func makeFixture(
        text: String = "Draft",
        service: FakeChatVoiceInputService,
        lifecycleController: VoiceInputLifecycleController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ChatVoiceInputTestFixture {
        let clock = TestChatVoiceInputClock()
        let fixture = ChatVoiceInputTestFixture(
            service: service,
            clock: clock,
            lifecycleController: lifecycleController
        )
        let coordinator = ChatVoiceInputCoordinator(
            service: service,
            lifecycleController: lifecycleController,
            clock: clock,
            supportedArchitecture: true,
            accessibilityAnnouncer: { [weak fixture] message in
                fixture?.announcements.append(message)
            },
            flushDraftFromEditor: { [weak fixture] in
                fixture?.flushCount += 1
            }
        )
        fixture.coordinator = coordinator
        coordinator.updateComposerContext(ChatVoiceInputComposerContext(
            draftIdentity: "voice-test-draft",
            inputDraftRevision: 0,
            attachmentIDs: [],
            workingDirectory: "/tmp/alveary-voice-tests"
        ))

        let controller = makeVoiceEditorController(text: text, coordinator: coordinator)
        let editor = try XCTUnwrap(controller.view, file: file, line: line)
        mount(editor: editor, controller: controller, fixture: fixture)
        return fixture
    }

    func markModelReady(_ fixture: ChatVoiceInputTestFixture) {
        fixture.service.setModelReady(true)
        fixture.coordinator.modelIsReady = true
    }

    func startRecording(
        _ fixture: ChatVoiceInputTestFixture,
        source: ChatVoiceInputActivationSource = .mouse
    ) async {
        markModelReady(fixture)
        XCTAssertTrue(fixture.coordinator.physicalPress(source))
        await waitUntil { fixture.coordinator.phase == .recording }
    }

    func reconfigureVoiceEditor(
        _ fixture: ChatVoiceInputTestFixture,
        text: String,
        inputDraftRevision: Int,
        isVoiceInteractionLocked: Bool = false
    ) {
        fixture.controller.configure(voiceEditorConfiguration(
            text: text,
            inputDraftRevision: inputDraftRevision,
            isVoiceInteractionLocked: isVoiceInteractionLocked,
            coordinator: fixture.coordinator
        ))
    }

    func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<500 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not met.", file: file, line: line)
    }

    private func makeVoiceEditorController(
        text: String,
        coordinator: ChatVoiceInputCoordinator
    ) -> AppKitChatComposerEditorController {
        let controller = AppKitChatComposerEditorController()
        controller.configure(voiceEditorConfiguration(
            text: text,
            inputDraftRevision: 0,
            coordinator: coordinator
        ))
        return controller
    }

    private func voiceEditorConfiguration(
        text: String,
        inputDraftRevision: Int,
        isVoiceInteractionLocked: Bool = false,
        coordinator: ChatVoiceInputCoordinator
    ) -> AppKitChatComposerBodyConfiguration {
        AppKitChatComposerBodyConfiguration(
            text: text,
            draftIdentity: "voice-test-draft",
            inputDraftRevision: inputDraftRevision,
            isTextEffectivelyEmpty: ChatComposerTextSupport.isEffectivelyEmpty(text),
            mode: .idle,
            defaultEnterBehavior: .queue,
            isStopConfirmationArmed: false,
            supportsMidTurnSteering: true,
            isProjectTrustBlocked: false,
            isHandoffSteeringPromptActive: false,
            isHandoffOutputPromptActive: false,
            handoffSteeringCountdown: nil,
            sendCountdown: nil,
            hasQueuedMessages: false,
            hasTopContent: false,
            workingDirectory: "/tmp/alveary-voice-tests",
            requestFirstResponder: nil,
            isVoiceInteractionLocked: isVoiceInteractionLocked,
            voiceEditorHandle: coordinator.editorHandle,
            onVoiceEscape: { [weak coordinator] in coordinator?.cancelFromEscape() ?? false },
            onVoiceInputAvailabilityChange: { [weak coordinator] in
                coordinator?.invalidatePendingActivationIntent()
            },
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onSubmit: {},
            onSteer: {},
            onStop: {},
            onStopConfirmationChange: { _ in },
            onFocusRequestConsumed: { _ in }
        )
    }

    private func mount(
        editor: BlockInputView,
        controller: AppKitChatComposerEditorController,
        fixture: ChatVoiceInputTestFixture
    ) {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 160)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        let contentView = NSView(frame: frame)
        window.contentView = contentView
        editor.frame = frame
        contentView.addSubview(editor)
        contentView.layoutSubtreeIfNeeded()
        fixture.controller = controller
        fixture.editor = editor
        fixture.window = window
    }
}

final class FakeChatVoiceInputService: VoiceInputService, @unchecked Sendable {
    private struct PreparationCall {
        let progress: [VoiceInputPreparationProgress]
        let suspends: Bool
        let error: Error?
        let result: VoiceInputPreparationResult
        let ignoresCancellation: Bool
    }

    struct State {
        var prepareCallCount = 0
        var beginRecognitionCallCount = 0
        var stopRecognitionCallCount = 0
        var cancelRecognitionCallCount = 0
        var shutdownCaptureCallCount = 0
        var beginRecognitionError: Error?
        var repeatsBeginRecognitionError = false
        var suspendsBegin = false
        var pendingBegin: CheckedContinuation<VoiceInputRecognitionSession, Error>?
        var pendingBeginSession: VoiceInputRecognitionSession?
        var suspendsCancel = false
        var pendingCancel: CheckedContinuation<Void, Never>?
        var cancelCaptureCallCount = 0
        var updateHandler: VoiceInputRecognitionUpdateHandler?
        var activeSession: VoiceInputRecognitionSession?
        var stopResult = VoiceInputRecognitionResult(
            transcript: nil,
            termination: .committed,
            error: nil
        )
        var suspendsStop = false
        var pendingStop: CheckedContinuation<VoiceInputRecognitionResult, Never>?
        var suspendsPrepare = false
        var ignoresPreparationCancellation = false
        var pendingPrepare: CheckedContinuation<Void, Never>?
        var preparationError: Error?
        var preparationProgress: [VoiceInputPreparationProgress] = [
            .checkingPermission,
            .checkingModel,
            .loadingModel,
            .ready
        ]
        var preparationResult = VoiceInputPreparationResult(
            source: .validatedCache,
            requestedMicrophonePermission: false
        )
        var modelIsReady = false
        var pendingPreparationAdmissionCount = 0
        var preparationParticipantCount = 0
    }
    let lock = NSLock()
    var state = State()
    var prepareCallCount: Int {
        lock.withLock { state.prepareCallCount }
    }

    var beginRecognitionCallCount: Int {
        lock.withLock { state.beginRecognitionCallCount }
    }

    var stopRecognitionCallCount: Int {
        lock.withLock { state.stopRecognitionCallCount }
    }

    var cancelRecognitionCallCount: Int {
        lock.withLock { state.cancelRecognitionCallCount }
    }

    var cancelCaptureCallCount: Int {
        lock.withLock { state.cancelCaptureCallCount }
    }

    var hasPendingStop: Bool {
        lock.withLock { state.pendingStop != nil }
    }
    var hasPendingPrepare: Bool {
        lock.withLock { state.pendingPrepare != nil }
    }

    var hasPendingBegin: Bool {
        lock.withLock { state.pendingBegin != nil }
    }

    var hasPendingCancel: Bool {
        lock.withLock { state.pendingCancel != nil }
    }

    var shutdownCaptureCallCount: Int {
        lock.withLock { state.shutdownCaptureCallCount }
    }

    func admitPreparation(requiringPreparation: Bool) -> VoiceInputPreparationAdmission {
        lock.withLock {
            guard state.pendingPreparationAdmissionCount == 0,
                  state.preparationParticipantCount == 0 else {
                return .busy
            }
            if state.modelIsReady, !requiringPreparation {
                return .ready
            }
            state.pendingPreparationAdmissionCount = 1
            return .initiated
        }
    }

    func prepare(
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparationResult {
        let preparation = try lock.withLock { () throws -> PreparationCall in
            guard state.pendingPreparationAdmissionCount == 1,
                  state.preparationParticipantCount == 0 else {
                throw VoiceInputServiceError.modelPreparationBusy
            }
            state.pendingPreparationAdmissionCount = 0
            state.preparationParticipantCount = 1
            state.prepareCallCount += 1
            return PreparationCall(
                progress: state.preparationProgress,
                suspends: state.suspendsPrepare,
                error: state.preparationError,
                result: state.preparationResult,
                ignoresCancellation: state.ignoresPreparationCancellation
            )
        }
        defer {
            lock.withLock {
                state.preparationParticipantCount = 0
            }
        }
        for update in preparation.progress {
            progress(update)
        }
        if preparation.suspends {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    state.pendingPrepare = continuation
                }
            }
        }
        if Task.isCancelled, !preparation.ignoresCancellation {
            throw CancellationError()
        }
        if let error = preparation.error {
            throw error
        }
        lock.withLock {
            state.modelIsReady = true
        }
        return preparation.result
    }

    func beginRecognition(
        attempt: VoiceInputRecognitionAttempt,
        onUpdate: @escaping VoiceInputRecognitionUpdateHandler
    ) async throws -> VoiceInputRecognitionSession {
        guard attempt.installCancellationHandler({ [weak self] in
            self?.recordStartupCancellation()
        }) else {
            throw VoiceInputServiceError.recognitionSessionExpired
        }
        let session = VoiceInputRecognitionSession()
        let result = lock.withLock { () -> Result<Bool, Error> in
            state.beginRecognitionCallCount += 1
            if let error = state.beginRecognitionError {
                if !state.repeatsBeginRecognitionError {
                    state.beginRecognitionError = nil
                }
                if case .modelLoad = error as? VoiceInputServiceError {
                    state.modelIsReady = false
                }
                return .failure(error)
            }
            state.activeSession = session
            state.updateHandler = onUpdate
            return .success(state.suspendsBegin)
        }
        let shouldSuspend = try result.get()
        guard shouldSuspend else {
            return session
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                state.pendingBegin = continuation
                state.pendingBeginSession = session
            }
        }
    }

    func stopRecognition(_ session: VoiceInputRecognitionSession) async -> VoiceInputRecognitionResult {
        let shouldSuspend = lock.withLock { () -> Bool in
            state.stopRecognitionCallCount += 1
            return state.suspendsStop
        }
        guard shouldSuspend else {
            return lock.withLock { state.stopResult }
        }
        return await withCheckedContinuation { continuation in
            lock.withLock {
                state.pendingStop = continuation
            }
        }
    }

    func cancelRecognition(_ session: VoiceInputRecognitionSession) async {
        let shouldSuspend = lock.withLock { () -> Bool in
            state.cancelRecognitionCallCount += 1
            return state.suspendsCancel
        }
        if shouldSuspend {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    state.pendingCancel = continuation
                }
            }
        }
        lock.withLock {
            if state.activeSession == session {
                state.activeSession = nil
                state.updateHandler = nil
            }
        }
    }

    func unloadIfIdle() async {
        setModelReady(false)
    }

    func shutdownCaptureSynchronously(for session: VoiceInputRecognitionSession) {
        lock.withLock {
            state.shutdownCaptureCallCount += 1
        }
    }

    func cancelCaptureSynchronously(for session: VoiceInputRecognitionSession) {
        lock.withLock {
            state.cancelCaptureCallCount += 1
        }
    }

    func prepareForTerminationSynchronously() {}
    func clearModelCache() async throws {
        setModelReady(false)
    }
    func shutdown() async {
        setModelReady(false)
    }

    private func recordStartupCancellation() {
        lock.withLock {
            state.shutdownCaptureCallCount += 1
        }
    }

    func emitPartial(_ text: String) {
        let delivery = lock.withLock { () -> (VoiceInputRecognitionUpdateHandler, VoiceInputRecognitionSession)? in
            guard let handler = state.updateHandler,
                  let session = state.activeSession else {
                return nil
            }
            return (handler, session)
        }
        guard let delivery else {
            return
        }
        delivery.0(.partial(session: delivery.1, text: text))
    }

    func emitCaptureFailure(_ error: VoiceInputServiceError) {
        let delivery = lock.withLock { () -> (VoiceInputRecognitionUpdateHandler, VoiceInputRecognitionSession)? in
            guard let handler = state.updateHandler,
                  let session = state.activeSession else {
                return nil
            }
            return (handler, session)
        }
        guard let delivery else { return }
        delivery.0(.captureFailed(session: delivery.1, error: error))
    }

    func resumePendingPrepare() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { state.pendingPrepare = nil }
            state.suspendsPrepare = false
            return state.pendingPrepare
        }
        continuation?.resume()
    }

    func resumePendingStop(with result: VoiceInputRecognitionResult) {
        let continuation = lock.withLock { () -> CheckedContinuation<VoiceInputRecognitionResult, Never>? in
            defer { state.pendingStop = nil }
            state.suspendsStop = false
            state.activeSession = nil
            state.updateHandler = nil
            return state.pendingStop
        }
        continuation?.resume(returning: result)
    }

    func resumePendingBegin() {
        let pending = lock.withLock { () -> (
            CheckedContinuation<VoiceInputRecognitionSession, Error>,
            VoiceInputRecognitionSession
        )? in
            guard let continuation = state.pendingBegin,
                  let session = state.pendingBeginSession else {
                return nil
            }
            state.pendingBegin = nil
            state.pendingBeginSession = nil
            state.suspendsBegin = false
            return (continuation, session)
        }
        guard let pending else { return }
        pending.0.resume(returning: pending.1)
    }

}
