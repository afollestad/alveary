import Foundation
import Observation
import SwiftData

@testable import Alveary

@MainActor
@Observable
final class InMemorySettingsService: SettingsService {
    private(set) var current: AppSettings
    private(set) var updateCount = 0

    init(current: AppSettings = AppSettings()) {
        self.current = current.normalized()
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        updateCount += 1
        transform(&current)
        current = current.normalized()
        NotificationCenter.default.post(name: .appSettingsChanged, object: self)
    }

    func updateRestoreSelection(threadID: PersistentIdentifier?, conversationID: PersistentIdentifier?) {
        guard current.lastOpenThreadID != threadID || current.lastOpenConversationID != conversationID else {
            return
        }

        current.lastOpenThreadID = threadID
        current.lastOpenConversationID = conversationID
        current = current.normalized()
    }

    func updateLastActiveProjectPath(_ path: String?) {
        guard current.lastActiveProjectPath != path else {
            return
        }
        current.lastActiveProjectPath = path
        current = current.normalized()
    }
}
