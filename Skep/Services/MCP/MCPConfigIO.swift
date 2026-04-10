import Foundation

enum MCPConfigIOError: Error, Equatable, Sendable {
    case unsupportedWriteFormat(MCPIntegrationDefinition.ConfigFormat)
}

extension MCPConfigIOError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedWriteFormat(let format):
            let formatName = switch format {
            case .json:
                "json"
            case .toml:
                "toml"
            }
            return "Writing MCP config format \(formatName) is not supported yet"
        }
    }
}

enum MCPConfigIO {
    static func readServers(from config: MCPIntegrationDefinition) throws -> ServerMap {
        let configPath = (config.configPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath),
              let data = FileManager.default.contents(atPath: configPath),
              !data.isEmpty else {
            return [:]
        }

        guard config.format != .toml else {
            return [:]
        }

        let rootObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return extractAtKeyPath(rootObject, keyPath: config.serversKeyPath)
    }

    static func writeServers(to config: MCPIntegrationDefinition, servers: ServerMap) throws {
        guard config.format != .toml else {
            throw MCPConfigIOError.unsupportedWriteFormat(.toml)
        }

        let configPath = (config.configPath as NSString).expandingTildeInPath
        let configURL = URL(fileURLWithPath: configPath)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        var rootObject: [String: Any]
        if let data = FileManager.default.contents(atPath: configPath), !data.isEmpty {
            rootObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        } else {
            rootObject = [:]
        }

        setAtKeyPath(&rootObject, keyPath: config.serversKeyPath, value: servers)
        var data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
        if data.last != 0x0A {
            data.append(0x0A)
        }
        try data.write(to: configURL, options: .atomic)
    }

    static func extractAtKeyPath(_ dictionary: [String: Any], keyPath: [String]) -> ServerMap {
        var current: Any = dictionary
        for key in keyPath {
            guard let nested = current as? [String: Any] else {
                return [:]
            }
            current = nested[key] as Any
        }

        guard let servers = current as? [String: Any] else {
            return [:]
        }

        return servers.compactMapValues { $0 as? [String: Any] }
    }

    static func setAtKeyPath(_ dictionary: inout [String: Any], keyPath: [String], value: Any) {
        guard let firstKey = keyPath.first else {
            return
        }

        if keyPath.count == 1 {
            dictionary[firstKey] = value
            return
        }

        var nested = dictionary[firstKey] as? [String: Any] ?? [:]
        setAtKeyPath(&nested, keyPath: Array(keyPath.dropFirst()), value: value)
        dictionary[firstKey] = nested
    }
}
