import Foundation

@testable import Alveary

extension FakeChatVoiceInputService {
    func emitStopped(_ result: VoiceInputRecognitionResult) {
        let delivery = lock.withLock { () -> (VoiceInputRecognitionUpdateHandler, VoiceInputRecognitionSession)? in
            guard let handler = state.updateHandler,
                  let session = state.activeSession else {
                return nil
            }
            return (handler, session)
        }
        guard let delivery else { return }
        delivery.0(.stopped(session: delivery.1, result: result))
    }

    func setStopResult(_ result: VoiceInputRecognitionResult) {
        lock.withLock {
            state.stopResult = result
        }
    }

    func setSuspendsStop(_ value: Bool) {
        lock.withLock {
            state.suspendsStop = value
        }
    }

    func setBeginRecognitionError(_ error: Error?) {
        lock.withLock {
            state.beginRecognitionError = error
            state.repeatsBeginRecognitionError = false
        }
    }

    func setPersistentBeginRecognitionError(_ error: Error?) {
        lock.withLock {
            state.beginRecognitionError = error
            state.repeatsBeginRecognitionError = error != nil
        }
    }

    func setSuspendsBegin(_ value: Bool) {
        lock.withLock {
            state.suspendsBegin = value
        }
    }

    func setSuspendsCancel(_ value: Bool) {
        lock.withLock {
            state.suspendsCancel = value
        }
    }

    func setPreparationProgress(_ progress: [VoiceInputPreparationProgress]) {
        lock.withLock {
            state.preparationProgress = progress
        }
    }

    func setPreparationError(_ error: Error?) {
        lock.withLock {
            state.preparationError = error
        }
    }

    func setPreparationResult(_ result: VoiceInputPreparationResult) {
        lock.withLock {
            state.preparationResult = result
        }
    }

    func setModelReady(_ value: Bool) {
        lock.withLock {
            state.modelIsReady = value
        }
    }

    func setSuspendsPrepare(_ value: Bool) {
        lock.withLock {
            state.suspendsPrepare = value
        }
    }

    func setIgnoresPreparationCancellation(_ value: Bool) {
        lock.withLock {
            state.ignoresPreparationCancellation = value
        }
    }

    func resumePendingCancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { state.pendingCancel = nil }
            state.suspendsCancel = false
            return state.pendingCancel
        }
        continuation?.resume()
    }

}
