import AgentCLIKit
import Foundation

/// JSON Schema builders shared by every `alveary_host` feature catalog.
///
/// Host tool schemas are always strict: an object root with `additionalProperties: false`,
/// so a provider cannot smuggle unadvertised fields past a handler's own validation.
enum HostToolSchema {
    static func strictObject(
        properties: [String: AgentCLIKit.JSONValue],
        required: [String]
    ) -> AgentCLIKit.JSONValue {
        var schema: [String: AgentCLIKit.JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(AgentCLIKit.JSONValue.string))
        }
        return .object(schema)
    }

    static func strictNestedUnionObject(
        properties: [String: AgentCLIKit.JSONValue],
        required: [String],
        branches: [AgentCLIKit.JSONValue]
    ) -> AgentCLIKit.JSONValue {
        // Keep unions nested: Claude drops tool definitions that use a union at the input-schema root.
        guard case .object(var schema) = strictObject(properties: properties, required: required) else {
            preconditionFailure("strictObject must produce an object schema")
        }
        schema["oneOf"] = .array(branches)
        return .object(schema)
    }

    static var stringSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("string")])
    }

    static var nonEmptyStringSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("string"), "minLength": .number(1)])
    }

    static var dateTimeSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("string"), "format": .string("date-time")])
    }

    static var booleanSchema: AgentCLIKit.JSONValue {
        .object(["type": .string("boolean")])
    }

    static func arraySchema(items: AgentCLIKit.JSONValue) -> AgentCLIKit.JSONValue {
        .object(["type": .string("array"), "items": items])
    }

    static func enumSchema(_ values: [String]) -> AgentCLIKit.JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(AgentCLIKit.JSONValue.string))
        ])
    }

    static func integerSchema(minimum: Int, maximum: Int? = nil) -> AgentCLIKit.JSONValue {
        var schema: [String: AgentCLIKit.JSONValue] = [
            "type": .string("integer"),
            "minimum": .number(Double(minimum))
        ]
        if let maximum {
            schema["maximum"] = .number(Double(maximum))
        }
        return .object(schema)
    }

    static var readOnlyAnnotations: AgentCLIKit.AgentHostToolAnnotations {
        AgentCLIKit.AgentHostToolAnnotations(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    }

    /// Mutates, but the change is undoable from Alveary's own UI, so it is not destructive.
    static var reversibleMutationAnnotations: AgentCLIKit.AgentHostToolAnnotations {
        AgentCLIKit.AgentHostToolAnnotations(
            readOnlyHint: false,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    }
}
