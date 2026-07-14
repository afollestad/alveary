import AgentCLIKit
import Foundation

extension AgentCLIKitEventMapper {
    static func serialized(_ value: AgentCLIKit.JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
