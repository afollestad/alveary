import Foundation

enum AgentSpeedMode: String, CaseIterable, Sendable, Equatable {
    case standard
    case fast

    init(normalizing rawValue: String?) {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = normalized.flatMap(Self.init(rawValue:)) ?? .standard
    }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .fast:
            return "Fast"
        }
    }
}
