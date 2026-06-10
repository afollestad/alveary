import Foundation
import SwiftData

@MainActor
protocol SettingsService: AnyObject, Sendable {
    var current: AppSettings { get }
    func update(_ transform: (inout AppSettings) -> Void)
    func updateRestoreSelection(threadID: PersistentIdentifier?, conversationID: PersistentIdentifier?)
}

extension Notification.Name {
    static let appSettingsChanged = Notification.Name("appSettingsChanged")
}
