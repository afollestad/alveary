import Foundation

struct TurnAwakeSettings: Codable, Sendable, Equatable {
    var enabled = false
    var preventDisplaySleep = true

    init(enabled: Bool = false, preventDisplaySleep: Bool = true) {
        self.enabled = enabled
        self.preventDisplaySleep = preventDisplaySleep
    }

    func normalized() -> TurnAwakeSettings {
        self
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case preventDisplaySleep
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        preventDisplaySleep = try container.decodeIfPresent(Bool.self, forKey: .preventDisplaySleep) ?? preventDisplaySleep
    }
}
