@testable import Alveary

extension SidebarMockWorktreeManager {
    enum MockError: Error, Sendable, Equatable {
        case createFailed
        case prepareForkContextFailed
        case removeFailed
        case removeAllFailed
        case listFailed
    }
}
