import AgentCLIKit
import Foundation

enum HostToolRequestError: Error, Equatable, LocalizedError, Sendable {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            message
        }
    }
}

/// Reads a tool-argument object with the strictness the AGENTS guidance requires: every key is
/// allowlisted and every value type-checked, whatever the advertised JSON Schema promised.
struct StrictHostToolObject {
    let values: [String: AgentCLIKit.JSONValue]
    let path: String

    init(_ values: [String: AgentCLIKit.JSONValue], path: String) {
        self.values = values
        self.path = path
    }

    func requireOnly(_ allowedKeys: Set<String>) throws {
        let unknownKeys = Set(values.keys).subtracting(allowedKeys).sorted()
        guard unknownKeys.isEmpty else {
            throw HostToolRequestError.invalidArguments(
                "\(path) contains unsupported field(s): \(unknownKeys.joined(separator: ", "))."
            )
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard case .string(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be a string.")
        }
        return value
    }

    func requiredNonEmptyString(_ key: String) throws -> String {
        let value = try requiredString(key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw invalid("\(path).\(key) must not be empty.")
        }
        return value
    }

    func optionalNonEmptyString(_ key: String) throws -> String? {
        guard values[key] != nil else {
            return nil
        }
        return try requiredNonEmptyString(key)
    }

    func requiredBool(_ key: String) throws -> Bool {
        guard case .bool(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be a boolean.")
        }
        return value
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard values[key] != nil else {
            return nil
        }
        return try requiredBool(key)
    }

    func requiredObject(_ key: String) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be an object.")
        }
        return value
    }

    func requiredArray(_ key: String) throws -> [AgentCLIKit.JSONValue] {
        guard case .array(let value)? = values[key] else {
            throw invalid("\(path).\(key) must be an array.")
        }
        return value
    }

    func optionalObject(_ key: String) throws -> [String: AgentCLIKit.JSONValue]? {
        guard values[key] != nil else {
            return nil
        }
        return try requiredObject(key)
    }

    func optionalArray(_ key: String) throws -> [AgentCLIKit.JSONValue]? {
        guard values[key] != nil else {
            return nil
        }
        return try requiredArray(key)
    }

    func requiredInteger(_ key: String) throws -> Int {
        guard case .number(let value)? = values[key],
              value.isFinite,
              value.rounded() == value,
              let integer = Int(exactly: value) else {
            throw invalid("\(path).\(key) must be an integer.")
        }
        return integer
    }

    func requiredPositiveInteger(_ key: String) throws -> Int {
        let value = try requiredInteger(key)
        guard value >= 1 else {
            throw invalid("\(path).\(key) must be at least 1.")
        }
        return value
    }

    private func invalid(_ message: String) -> HostToolRequestError {
        .invalidArguments(message)
    }
}
