import Foundation

extension DefaultAgentsManager {
    nonisolated func readAgentOutput(stdout: FileHandle, stderr: FileHandle, adapter: AgentAdapter) -> AsyncStream<ConversationEvent> {
        return AsyncStream { continuation in
            let stderrBuffer = StderrBuffer(maxLines: 20)
            let coordinator = AgentStreamCoordinator(
                continuation: continuation,
                adapter: adapter,
                stderrBuffer: stderrBuffer
            )
            let stderrPump = PipeLinePump(handle: stderr) { lineData in
                stderrBuffer.append(utf8String(from: lineData))
                return true
            } onFinish: {
                coordinator.markStderrFinished()
            }
            let stdoutPump = PipeLinePump(handle: stdout) { lineData in
                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    let trimmed = utf8String(from: lineData)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        return true
                    }

                    coordinator.recordMalformedLine(prefix: String(trimmed.prefix(240)))
                    return false
                }

                let events = adapter.decode(json)
                for event in events {
                    continuation.yield(event)
                }
                return !events.contains(where: isToolDeferredEvent)
            } onFinish: {
                coordinator.markStdoutFinished()
            }

            stderrPump.start()
            stdoutPump.start()

            continuation.onTermination = { _ in
                stderrPump.cancel()
                stdoutPump.cancel()
                coordinator.cancel()
            }
        }
    }
}

private func utf8String(from data: Data) -> String {
    String(bytes: data, encoding: .utf8) ?? ""
}

private func isToolDeferredEvent(_ event: ConversationEvent) -> Bool {
    guard case .tokens(_, _, _, _, let stopReason, _, _, _) = event else {
        return false
    }
    return stopReason == "tool_deferred"
}

private final class AgentStreamCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<ConversationEvent>.Continuation
    private let adapter: AgentAdapter
    private let stderrBuffer: StderrBuffer

    private var stdoutFinished = false
    private var stderrFinished = false
    private var malformedLinePrefix: String?
    private var isCancelled = false
    private var hasFinished = false

    init(
        continuation: AsyncStream<ConversationEvent>.Continuation,
        adapter: AgentAdapter,
        stderrBuffer: StderrBuffer
    ) {
        self.continuation = continuation
        self.adapter = adapter
        self.stderrBuffer = stderrBuffer
    }

    func recordMalformedLine(prefix: String) {
        lock.lock()
        if malformedLinePrefix == nil {
            malformedLinePrefix = prefix
        }
        lock.unlock()
    }

    func markStdoutFinished() {
        finish(kind: .stdout)
    }

    func markStderrFinished() {
        finish(kind: .stderr)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        hasFinished = true
        lock.unlock()
    }

    private func finish(kind: FinishedKind) {
        let shouldFinalize: Bool
        let malformedLinePrefix: String?

        lock.lock()
        switch kind {
        case .stdout:
            stdoutFinished = true
        case .stderr:
            stderrFinished = true
        }
        shouldFinalize = !hasFinished && !isCancelled && stdoutFinished && stderrFinished
        if shouldFinalize {
            hasFinished = true
        }
        malformedLinePrefix = self.malformedLinePrefix
        lock.unlock()

        guard shouldFinalize else {
            return
        }

        if let malformedLinePrefix {
            let stderrTail = stderrBuffer.lastLines.joined(separator: "\n")
            let message = if stderrTail.isEmpty {
                "Malformed agent stdout line: \(malformedLinePrefix)"
            } else {
                "Malformed agent stdout line: \(malformedLinePrefix)\n\nStderr:\n\(stderrTail)"
            }
            continuation.yield(.error(message: message))
        }

        for event in adapter.finalize() {
            continuation.yield(event)
        }
        continuation.finish()
    }

    private enum FinishedKind {
        case stdout
        case stderr
    }
}

private final class PipeLinePump: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let onLine: @Sendable (Data) -> Bool
    private let onFinish: @Sendable () -> Void

    private var buffer = Data()
    private var hasFinished = false

    init(
        handle: FileHandle,
        onLine: @escaping @Sendable (Data) -> Bool,
        onFinish: @escaping @Sendable () -> Void
    ) {
        self.handle = handle
        self.onLine = onLine
        self.onFinish = onFinish
    }

    func start() {
        handle.readabilityHandler = { [weak self] handle in
            self?.handleReadable(handle)
        }
    }

    func cancel() {
        finish(flushPendingLine: false)
    }

    private func handleReadable(_ handle: FileHandle) {
        let chunk = handle.availableData
        if chunk.isEmpty {
            finish(flushPendingLine: true)
            return
        }

        let lines = appendAndTakeLines(from: chunk)
        for line in lines where !onLine(line) {
            finish(flushPendingLine: false)
            return
        }
    }

    private func appendAndTakeLines(from chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        guard !hasFinished else {
            return []
        }

        buffer.append(chunk)

        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newlineIndex])
            if line.last == 0x0D {
                line.removeLast()
            }
            lines.append(line)
            buffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    private func finish(flushPendingLine: Bool) {
        let pendingLine: Data?

        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }

        hasFinished = true
        handle.readabilityHandler = nil
        if flushPendingLine, !buffer.isEmpty {
            pendingLine = buffer.last == 0x0D ? Data(buffer.dropLast()) : buffer
        } else {
            pendingLine = nil
        }
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()

        if let pendingLine, !pendingLine.isEmpty {
            _ = onLine(pendingLine)
        }
        onFinish()
    }
}

private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []
    private var writeIndex = 0
    private var isFull = false
    private let capacity: Int

    init(maxLines: Int) {
        self.capacity = maxLines
        buffer.reserveCapacity(maxLines)
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }

        if buffer.count < capacity {
            buffer.append(line)
            if buffer.count == capacity {
                isFull = true
            }
        } else {
            buffer[writeIndex] = line
        }
        writeIndex = (writeIndex + 1) % capacity
    }

    var lastLines: [String] {
        lock.lock()
        defer { lock.unlock() }

        if !isFull {
            return buffer
        }

        return Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
    }
}
