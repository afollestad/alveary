import Foundation

@testable import Alveary

final class SidebarLockedStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: ActivitySignal] = [:]

    func set(_ status: ActivitySignal, for conversationId: String) {
        lock.lock()
        values[conversationId] = status
        lock.unlock()
    }

    func status(for conversationId: String) -> ActivitySignal {
        lock.lock()
        let status = values[conversationId] ?? .neutral
        lock.unlock()
        return status
    }

    func snapshot() -> [String: ActivitySignal] {
        lock.lock()
        let snapshot = values
        lock.unlock()
        return snapshot
    }
}
