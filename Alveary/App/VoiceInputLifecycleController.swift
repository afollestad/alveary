import Foundation

extension Notification.Name {
    static let voiceInputComposerInteractionLockChanged = Notification.Name(
        "Alveary.voiceInputComposerInteractionLockChanged"
    )
    static let voiceInputOwnershipChanged = Notification.Name(
        "Alveary.voiceInputOwnershipChanged"
    )
}

@MainActor
protocol VoiceInputComposerSink: AnyObject {
    var isVoiceComposerInteractionLocked: Bool { get }
    var isModelPreparationModalPresented: Bool { get }
    func forceVoiceInputCommitSynchronously()
}

extension VoiceInputComposerSink {
    var isVoiceComposerInteractionLocked: Bool { true }
    var isModelPreparationModalPresented: Bool { false }
}

/// Bridges app-lifecycle events to the currently active composer without making
/// the app delegate depend on view ownership details.
@MainActor
final class VoiceInputLifecycleController {
    let service: any VoiceInputService

    private var registeredComposerSinks: [WeakVoiceInputComposerSink] = []
    private var lastPublishedInteractionLockState = false

    var isComposerInteractionLocked: Bool {
        pruneReleasedComposerSinks()
        return registeredComposerSinks.contains { sink in
            sink.value?.isVoiceComposerInteractionLocked == true
        }
    }

    var isModelPreparationModalPresented: Bool {
        pruneReleasedComposerSinks()
        return registeredComposerSinks.contains { sink in
            sink.value?.isModelPreparationModalPresented == true
        }
    }

    func isVoiceInputOwned(byAnotherComposer sink: any VoiceInputComposerSink) -> Bool {
        pruneReleasedComposerSinks()
        return registeredComposerSinks.contains { registeredSink in
            guard let value = registeredSink.value else { return false }
            return value !== sink
        }
    }

    init(service: any VoiceInputService) {
        self.service = service
    }

    func setActiveComposerSink(_ sink: (any VoiceInputComposerSink)?) {
        pruneReleasedComposerSinks()
        guard let sink else {
            registeredComposerSinks.removeAll()
            publishInteractionLockChangeIfNeeded()
            return
        }
        if !registeredComposerSinks.contains(where: { $0.value === sink }) {
            registeredComposerSinks.append(WeakVoiceInputComposerSink(sink))
            publishOwnershipChange()
        }
        publishInteractionLockChangeIfNeeded()
    }

    func clearActiveComposerSink(_ sink: any VoiceInputComposerSink) {
        let previousCount = registeredComposerSinks.count
        registeredComposerSinks.removeAll { registeredSink in
            registeredSink.value == nil || registeredSink.value === sink
        }
        if registeredComposerSinks.count != previousCount {
            publishOwnershipChange()
        }
        publishInteractionLockChangeIfNeeded()
    }

    func composerSinkStateDidChange(_ sink: any VoiceInputComposerSink) {
        pruneReleasedComposerSinks()
        guard registeredComposerSinks.contains(where: { $0.value === sink }) else {
            return
        }
        publishInteractionLockChangeIfNeeded()
    }

    /// Stops admission and the hardware tap synchronously so termination cannot
    /// race a late audio callback. Inference cleanup continues asynchronously.
    func teardownSynchronously() {
        let sinks = registeredComposerSinks.compactMap(\.value)
        registeredComposerSinks.removeAll()
        if !sinks.isEmpty {
            publishOwnershipChange()
        }
        publishInteractionLockChangeIfNeeded()
        sinks.forEach { $0.forceVoiceInputCommitSynchronously() }
        service.prepareForTerminationSynchronously()
        let service = service
        Task.detached(priority: .utility) {
            await service.shutdown()
        }
    }

    private func pruneReleasedComposerSinks() {
        registeredComposerSinks.removeAll { $0.value == nil }
    }

    private func publishInteractionLockChangeIfNeeded() {
        let isLocked = registeredComposerSinks.contains { sink in
            sink.value?.isVoiceComposerInteractionLocked == true
        }
        guard isLocked != lastPublishedInteractionLockState else {
            return
        }
        lastPublishedInteractionLockState = isLocked
        NotificationCenter.default.post(name: .voiceInputComposerInteractionLockChanged, object: self)
    }

    private func publishOwnershipChange() {
        NotificationCenter.default.post(name: .voiceInputOwnershipChanged, object: self)
    }
}

private final class WeakVoiceInputComposerSink {
    weak var value: (any VoiceInputComposerSink)?

    init(_ value: any VoiceInputComposerSink) {
        self.value = value
    }
}
