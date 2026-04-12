import Foundation

typealias RawServerEntry = [String: Any]
typealias ServerMap = [String: RawServerEntry]

enum MCPAdapter {
    static func adaptForward(_ type: MCPAdapterType, servers: ServerMap) -> ServerMap {
        switch type {
        case .passthrough:
            return servers
        }
    }

    static func adaptReverse(_ type: MCPAdapterType, servers: ServerMap) -> ServerMap {
        switch type {
        case .passthrough:
            return servers
        }
    }
}
