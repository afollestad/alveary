import AgentCLIKit
import Foundation

/// Shared decoding for a host MCP tool call's persisted input and output.
///
/// Claude Code serializes a host tool's `structuredContent` with `JSON.stringify` and emits
/// that as the tool result text, so the persisted output is the tool's declared output schema
/// verbatim. Codex emits the plain-text fallback instead, which simply fails to decode here.
enum HostToolWidgetJSON {
    static func object(from string: String?) -> [String: AgentCLIKit.JSONValue]? {
        guard case let .object(object)? = value(from: string) else {
            return nil
        }
        return object
    }

    static func string(_ value: AgentCLIKit.JSONValue?) -> String? {
        guard case let .string(string)? = value else {
            return nil
        }
        return string
    }

    static func integer(_ value: AgentCLIKit.JSONValue?) -> Int? {
        guard case let .number(number)? = value else {
            return nil
        }
        return Int(number)
    }

    /// The provider's plain-text fallback: a result that is not JSON at all. `nil` when the
    /// output did parse, so callers prefer the receipt's own message over its serialization.
    static func plainText(from output: String?) -> String? {
        guard let output, object(from: output) == nil else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func value(from string: String?) -> AgentCLIKit.JSONValue? {
        guard let string,
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data)
    }
}
