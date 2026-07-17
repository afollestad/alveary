@preconcurrency import AVFoundation
import AppKit
import Foundation

protocol VoiceInputAudioCaptureBackend: AnyObject, Sendable {
    var format: AVAudioFormat { get }

    func installTap(
        frameCount: AVAudioFrameCount,
        format: AVAudioFormat,
        generation: UInt64,
        queue: VoiceInputPCMQueue
    ) throws
    func prepare()
    func start() throws
    func installObservers(queue: VoiceInputPCMQueue)
    func stop()
    func removeTap()
    func removeObservers()
    func reset()
}

final class AVAudioEngineVoiceInputCaptureBackend: VoiceInputAudioCaptureBackend, @unchecked Sendable {
    let format: AVAudioFormat

    private let engine: AVAudioEngine
    private let input: AVAudioInputNode
    private let capturedDeviceID: String?
    private let observerLock = NSLock()
    private var observerTokens: [NSObjectProtocol] = []

    init(engine: AVAudioEngine) {
        self.engine = engine
        input = engine.inputNode
        format = input.outputFormat(forBus: 0)
        capturedDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
    }

    func installTap(
        frameCount: AVAudioFrameCount,
        format: AVAudioFormat,
        generation: UInt64,
        queue: VoiceInputPCMQueue
    ) throws {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            try input.installAudioTap(onBus: 0, bufferSize: frameCount, format: format) { buffer, _ in
                VoiceInputCopiedPCM.copyIfAdmitted(buffer, generation: generation, queue: queue)
            }
            return
        }
        #endif

        input.installTap(onBus: 0, bufferSize: frameCount, format: format) { buffer, _ in
            VoiceInputCopiedPCM.copyIfAdmitted(buffer, generation: generation, queue: queue)
        }
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func installObservers(queue: VoiceInputPCMQueue) {
        let configuration = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            queue.fail(.deviceConfigurationChanged)
        }
        let sleep = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { _ in
            queue.fail(.systemSleep)
        }
        let disconnected = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [capturedDeviceID] notification in
            guard let device = notification.object as? AVCaptureDevice,
                  let capturedDeviceID,
                  device.uniqueID == capturedDeviceID else {
                return
            }
            queue.fail(.deviceConfigurationChanged)
        }
        observerLock.withLock {
            observerTokens = [configuration, sleep, disconnected]
        }
    }

    func stop() {
        engine.stop()
    }

    func removeTap() {
        input.removeTap(onBus: 0)
    }

    func removeObservers() {
        let tokens = observerLock.withLock { () -> [NSObjectProtocol] in
            defer { observerTokens.removeAll() }
            return observerTokens
        }
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func reset() {
        engine.reset()
    }
}
