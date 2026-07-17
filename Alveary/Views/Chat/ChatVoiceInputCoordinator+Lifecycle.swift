@preconcurrency import AppKit
import BlockInputKit
import Foundation

extension ChatVoiceInputCoordinator {
    static let voiceInputOwnedElsewhereMessage =
        "Voice input is active in another thread. Stop it or wait for cleanup to finish."
    static let voiceInputPreparationBusyMessage =
        "Voice input cleanup is still finishing. Try dictation again in a moment."

    static func postAccessibilityAnnouncement(_ message: String) {
        guard let application = NSApp else {
            return
        }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    func refreshVoiceInputOwnership() {
        isVoiceInputOwnedElsewhere = lifecycleController.isVoiceInputOwned(byAnotherComposer: self)
    }

    @discardableResult
    func beginPendingStartupCleanup() -> Bool {
        guard phase == .starting,
              startupTask != nil else {
            return false
        }
        installReleaseBarrierForHeldSource()
        advanceGeneration()
        preparationTask?.cancel()
        recordingLimitTask?.cancel()
        finalizationTimeoutTask?.cancel()
        startupRelease = nil
        startupLifetime.invalidate()
        phase = .cleanup
        return true
    }

    func finishPendingStartupCleanup(generation: UInt64) {
        guard generation != sessionGeneration,
              phase == .cleanup else {
            return
        }
        startupTask = nil
        startupRelease = nil
        phase = modelIsReady ? .ready : .idle
        clearPhysicalPress()
        lifecycleController.clearActiveComposerSink(self)
    }

    func startRecordingLimit(generation: UInt64) {
        let clock = clock
        recordingLimitTask?.cancel()
        recordingLimitTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.recordingLimit)
            } catch {
                return
            }
            guard let self else { return }
            self.recordingLimitReached(generation: generation)
        }
    }

    func recordingLimitReached(generation: UInt64) {
        guard generation == sessionGeneration,
              phase == .recording else {
            return
        }
        installReleaseBarrierForHeldSource()
        notice = ChatVoiceInputNotice(
            message: "Dictation stopped after the 10-minute limit.",
            severity: .warning,
            recovery: nil
        )
        requestStopAndCommit()
        announce("Dictation stopped after the 10-minute limit")
    }

    func installReleaseBarrierForHeldSource() {
        if let activeSource, isSourceHeld {
            releaseBarrier.insert(activeSource)
        }
        clearPhysicalPress()
        isLatched = false
    }

    func clearPendingGestureIntent() {
        pendingPreparationActivation = nil
        if phase == .starting {
            startupRelease = StartupRelease(forced: true, duration: Self.holdThreshold)
        }
        clearPhysicalPress()
    }

    func clearPhysicalPress() {
        activeSource = nil
        pressedAt = nil
        isSourceHeld = false
    }

    func advanceGeneration() {
        sessionGeneration &+= 1
        acceptsPartialDelivery = false
        pendingStartupRecognitionUpdates.removeAll()
    }

    func present(error: Error) {
        let presentedNotice = voiceInputNotice(for: error)
        notice = presentedNotice
        announce(presentedNotice.message)
    }

    func voiceInputNotice(for error: Error) -> ChatVoiceInputNotice {
        let serviceError = error as? VoiceInputServiceError
        let message = serviceError?.errorDescription ?? error.localizedDescription
        let recoveryMessage = recoveryMessage(for: serviceError, fallback: message)
        return ChatVoiceInputNotice(
            message: recoveryMessage,
            severity: .error,
            recovery: serviceError?.isPermissionDenial == true ? .microphoneSettings : nil
        )
    }

    func present(message: String, severity: ChatVoiceInputNotice.Severity) {
        notice = ChatVoiceInputNotice(message: message, severity: severity, recovery: nil)
        announce(message)
    }

    func recoveryMessage(for error: VoiceInputServiceError?, fallback: String) -> String {
        switch error {
        case .permissionDenied:
            "Microphone access is off. Allow Alveary in System Settings to use dictation."
        case .permissionRestricted:
            "Microphone access is restricted on this Mac."
        case .noInputDevice:
            "No microphone is available. Connect or enable an input device and try again."
        case .insufficientDiskSpace, .diskFull:
            "There is not enough free disk space to prepare the voice model."
        case .modelDownload:
            "The voice model could not be downloaded. Check your connection and try again."
        case .modelCache, .modelLoad:
            "The local voice model could not be loaded. Try again to repair it."
        case .captureQueueOverflow:
            "Dictation stopped because audio processing could not keep up."
        case .unsupportedArchitecture:
            "Voice input requires a Mac with Apple silicon."
        case nil:
            fallback
        default:
            fallback
        }
    }

    func unavailableSelectionMessage(_ reason: BlockInputProvisionalTextUnavailable) -> String {
        switch reason {
        case .unsupportedSelection, .unsupportedBlockKind, .invalidSelectionRange:
            "Place the cursor in text, or select text within one block, before dictating."
        case .editorReadOnly:
            "The message editor is read-only right now."
        case .mutationUIVisible:
            "Close the editor popover before dictating."
        case .editorNotMounted, .targetBlockUnavailable, .noEditableTextBlock, .sessionAlreadyActive:
            "The message editor is not available for dictation."
        }
    }

    func announce(_ message: String) {
        accessibilityAnnouncer(message)
    }

    static func normalizedTranscript(_ text: String) -> String {
        text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }
}
