import Foundation
import SwiftData

extension SidebarViewModel {
    func postThreadLifecycleChanged(threadID: PersistentIdentifier, mode: AgentThreadMode) {
        NotificationCenter.default.post(
            name: .threadLifecycleChanged,
            object: nil,
            userInfo: [
                ThreadLifecycleNotificationKey.threadID: threadID,
                ThreadLifecycleNotificationKey.mode: mode.rawValue
            ]
        )
    }
}
