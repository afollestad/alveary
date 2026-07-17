import BlockInputKit
import Foundation

extension ChatVoiceInputCoordinator {
    @discardableResult
    func beginForcedPendingStartupCleanup() -> Bool {
        guard phase == .starting else {
            return false
        }
        let preferredTranscript = preferredPendingStartupTranscript()
        guard beginPendingStartupCleanup() else {
            return false
        }
        let draftFinishOutcome = finishPendingStartupTranscriptSynchronously(preferredTranscript)
        if draftFinishOutcome == .invalidated {
            presentDraftChangedNotice()
        }
        return true
    }

    func receiveRecognitionUpdate(_ update: VoiceInputRecognitionUpdate, generation: UInt64) {
        guard generation == sessionGeneration else {
            return
        }
        if recognitionSession == nil, phase == .starting {
            pendingStartupRecognitionUpdates.append(update)
            return
        }
        switch update {
        case .partial(let session, let text):
            guard acceptsPartialDelivery,
                  recognitionSession == session else {
                return
            }
            applyPartial(text)
        case .captureFailed(let session, let error):
            guard recognitionSession == session else {
                return
            }
            installReleaseBarrierForHeldSource()
            notice = ChatVoiceInputNotice(
                message: error == .captureQueueOverflow ?
                    "Dictation stopped because audio processing could not keep up." :
                    (error.errorDescription ?? "Dictation stopped because the microphone failed."),
                severity: .error,
                recovery: nil
            )
            requestStopAndCommit()
        case .stopped(let session, let result):
            guard recognitionSession == session, phase == .recording else {
                return
            }
            installReleaseBarrierForHeldSource()
            acceptsPartialDelivery = false
            recordingLimitTask?.cancel()
            recordingLimitTask = nil
            finishRecognition(result, session: session, generation: generation)
        }
    }

    func applyPartial(_ rawText: String) {
        guard let provisionalSession else {
            return
        }
        let normalized = Self.normalizedTranscript(rawText)
        guard !normalized.isEmpty,
              normalized != latestNonemptyTranscript else {
            return
        }
        let replacement = insertionContext?.replacementText(for: normalized) ?? normalized
        switch editorHandle.updateProvisionalTextReplacement(provisionalSession, text: replacement) {
        case .applied, .unchanged:
            latestNonemptyTranscript = normalized
        case .invalidated:
            acceptsPartialDelivery = false
            self.provisionalSession = nil
            requestStopAfterInvalidation()
        }
    }

    func requestStopAndCommit() {
        guard let session = recognitionSession else {
            if phase == .starting {
                startupRelease = StartupRelease(forced: true, duration: Self.holdThreshold)
            }
            return
        }
        guard phase == .recording else {
            return
        }
        acceptsPartialDelivery = false
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        phase = .finalizing
        isLatched = false
        announce("Finalizing dictation")
        let generation = sessionGeneration
        startFinalizationTimeout(session: session, generation: generation)
        let service = service
        startupTask = Task { [weak self] in
            let result = await service.stopRecognition(session)
            guard let self else { return }
            self.finishRecognition(result, session: session, generation: generation)
        }
    }

    func requestStopAfterInvalidation() {
        guard let session = recognitionSession else {
            phase = .ready
            return
        }
        installReleaseBarrierForHeldSource()
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        phase = .cleanup
        service.shutdownCaptureSynchronously(for: session)
        let service = service
        startupTask = Task { [weak self] in
            _ = await service.stopRecognition(session)
            guard let self else { return }
            self.finishCleanup(session: session)
        }
        present(message: "Dictation stopped because the draft changed unexpectedly.", severity: .error)
    }

    func finishRecognition(
        _ result: VoiceInputRecognitionResult,
        session: VoiceInputRecognitionSession,
        generation: UInt64
    ) {
        guard recognitionSession == session else {
            return
        }
        startupTask = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        guard generation == sessionGeneration else {
            finishCleanup(session: session)
            return
        }
        let priorNotice = notice
        let finalTranscript = result.transcript.flatMap { transcript -> String? in
            let normalized = Self.normalizedTranscript(transcript)
            return normalized.isEmpty ? nil : normalized
        }
        let draftFinishOutcome = finishProvisionalSynchronously(
            preferredTranscript: finalTranscript ?? latestNonemptyTranscript
        )
        if draftFinishOutcome == .invalidated {
            presentDraftChangedNotice()
        } else if let error = result.error {
            let finalNotice = combinedFinalizationNotice(
                preserving: priorNotice,
                error: voiceInputNotice(for: error)
            )
            notice = finalNotice
            announce(finalNotice.message)
        }
        recognitionSession = nil
        insertionContext = nil
        latestNonemptyTranscript = nil
        phase = .ready
        clearPhysicalPress()
        lifecycleController.clearActiveComposerSink(self)
        announce("Dictation finished")
    }

    func startFinalizationTimeout(session: VoiceInputRecognitionSession, generation: UInt64) {
        let clock = clock
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.finalizationTimeout)
            } catch {
                return
            }
            guard let self else { return }
            self.finalizationDidTimeOut(session: session, generation: generation)
        }
    }

    func finalizationDidTimeOut(session: VoiceInputRecognitionSession, generation: UInt64) {
        guard generation == sessionGeneration,
              recognitionSession == session,
              phase == .finalizing else {
            return
        }
        let priorNotice = notice
        advanceGeneration()
        let draftFinishOutcome = finishProvisionalSynchronously(preferredTranscript: latestNonemptyTranscript)
        phase = .cleanup
        clearPhysicalPress()
        let timeoutNotice = finalizationTimeoutNotice(
            outcome: draftFinishOutcome,
            preserving: priorNotice
        )
        notice = timeoutNotice
        announce(timeoutNotice.message)
    }

    func finishCleanup(session: VoiceInputRecognitionSession) {
        guard recognitionSession == session else {
            return
        }
        startupTask = nil
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        recognitionSession = nil
        startupRelease = nil
        insertionContext = nil
        latestNonemptyTranscript = nil
        phase = modelIsReady ? .ready : .idle
        clearPhysicalPress()
        lifecycleController.clearActiveComposerSink(self)
    }

    @discardableResult
    func finishProvisionalSynchronously(
        preferredTranscript: String?
    ) -> ChatVoiceInputDraftFinishOutcome {
        guard let provisionalSession else {
            return .noTransaction
        }
        let intendedToCommit = preferredTranscript?.isEmpty == false
        let finishResult: BlockInputProvisionalTextFinishResult
        if let preferredTranscript, intendedToCommit {
            let replacement = insertionContext?.replacementText(for: preferredTranscript) ?? preferredTranscript
            switch editorHandle.updateProvisionalTextReplacement(provisionalSession, text: replacement) {
            case .applied, .unchanged:
                finishResult = editorHandle.finishProvisionalTextReplacement(
                    provisionalSession,
                    disposition: .commit
                )
            case .invalidated:
                finishResult = .invalidated
            }
        } else {
            finishResult = editorHandle.finishProvisionalTextReplacement(
                provisionalSession,
                disposition: .cancel
            )
        }
        self.provisionalSession = nil
        flushDraftFromEditor()
        switch finishResult {
        case .committed:
            return .committed
        case .cancelled:
            return .restored
        case .unchanged:
            return intendedToCommit ? .committed : .restored
        case .invalidated:
            return .invalidated
        }
    }

    func preferredPendingStartupTranscript() -> String? {
        var latestPartial: String?
        var latestFinal: String?
        for update in pendingStartupRecognitionUpdates {
            switch update {
            case .partial(_, let text):
                let normalized = Self.normalizedTranscript(text)
                if !normalized.isEmpty {
                    latestPartial = normalized
                }
            case .stopped(_, let result):
                guard let transcript = result.transcript else { continue }
                let normalized = Self.normalizedTranscript(transcript)
                if !normalized.isEmpty {
                    latestFinal = normalized
                }
            case .captureFailed:
                break
            }
        }
        return latestFinal ?? latestPartial
    }

    func finishPendingStartupTranscriptSynchronously(
        _ preferredTranscript: String?
    ) -> ChatVoiceInputDraftFinishOutcome {
        guard let preferredTranscript else {
            return .noTransaction
        }
        switch editorHandle.beginProvisionalTextReplacement() {
        case .started(let provisionalSession):
            self.provisionalSession = provisionalSession
            insertionContext = editorHandle.insertionContext()
            let outcome = finishProvisionalSynchronously(preferredTranscript: preferredTranscript)
            insertionContext = nil
            return outcome
        case .unavailable:
            return .invalidated
        }
    }

    func presentDraftChangedNotice() {
        present(message: "Dictation stopped because the draft changed unexpectedly.", severity: .error)
    }

    func finalizationTimeoutNotice(
        outcome: ChatVoiceInputDraftFinishOutcome,
        preserving priorNotice: ChatVoiceInputNotice?
    ) -> ChatVoiceInputNotice {
        let baseNotice: ChatVoiceInputNotice
        switch outcome {
        case .invalidated:
            baseNotice = ChatVoiceInputNotice(
                message: "Dictation stopped because the draft changed unexpectedly.",
                severity: .error,
                recovery: nil
            )
        case .committed:
            baseNotice = priorNotice ?? ChatVoiceInputNotice(
                message: "Dictation was committed.",
                severity: .warning,
                recovery: nil
            )
        case .restored:
            baseNotice = priorNotice ?? ChatVoiceInputNotice(
                message: "No speech was detected. The original draft was restored.",
                severity: .warning,
                recovery: nil
            )
        case .noTransaction:
            baseNotice = priorNotice ?? ChatVoiceInputNotice(
                message: "Dictation ended.",
                severity: .warning,
                recovery: nil
            )
        }
        let suffix = "Voice cleanup is still finishing."
        let message: String
        if baseNotice.message.hasSuffix(suffix) {
            message = baseNotice.message
        } else {
            message = appendingSentence(suffix, to: baseNotice.message)
        }
        return ChatVoiceInputNotice(
            message: message,
            severity: baseNotice.severity,
            recovery: baseNotice.recovery
        )
    }

    func combinedFinalizationNotice(
        preserving priorNotice: ChatVoiceInputNotice?,
        error: ChatVoiceInputNotice
    ) -> ChatVoiceInputNotice {
        guard let priorNotice else { return error }
        let message = priorNotice.message == error.message ?
            priorNotice.message :
            appendingSentence(error.message, to: priorNotice.message)
        return ChatVoiceInputNotice(
            message: message,
            severity: .error,
            recovery: error.recovery ?? priorNotice.recovery
        )
    }

    func appendingSentence(_ sentence: String, to message: String) -> String {
        guard !message.hasSuffix(sentence) else { return message }
        let hasTerminalPunctuation = message.last.map { [".", "!", "?", "…"].contains($0) } == true
        return message + (hasTerminalPunctuation ? " " : ". ") + sentence
    }
}
