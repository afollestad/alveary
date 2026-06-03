import Foundation

enum ThreadEnterDefaultBehavior: String, Codable, Sendable, CaseIterable {
    case queue
    case steer

    var label: String {
        switch self {
        case .queue:
            return "Queue"
        case .steer:
            return "Steer"
        }
    }
}
