import Foundation

typealias RawServerEntry = [String: Any]
typealias ServerMap = [String: RawServerEntry]

enum MCPAdapter {
    static func adaptForward(_ type: MCPAdapterType, servers: ServerMap) -> ServerMap {
        switch type {
        case .passthrough:
            return servers
        case .opencode:
            return servers.mapValues { canonical in
                var native = canonical
                let remote = canonical["type"] as? String == "http" || canonical["url"] != nil
                native["type"] = remote ? "remote" : "local"
                if let command = canonical["command"] as? String {
                    native["command"] = [command] + (canonical["args"] as? [String] ?? [])
                }
                native["args"] = nil
                native["environment"] = native.removeValue(forKey: "env")
                if let disabled = native.removeValue(forKey: "disabled") as? Bool {
                    native["enabled"] = !disabled
                }
                return native
            }
        }
    }

    static func adaptReverse(_ type: MCPAdapterType, servers: ServerMap) -> ServerMap {
        switch type {
        case .passthrough:
            return servers
        case .opencode:
            return servers.mapValues { native in
                var canonical = native
                canonical["type"] = native["type"] as? String == "remote" ? "http" : "stdio"
                if let command = native["command"] as? [String] {
                    canonical["command"] = command.first
                    canonical["args"] = Array(command.dropFirst())
                }
                canonical["env"] = canonical.removeValue(forKey: "environment")
                if let enabled = canonical.removeValue(forKey: "enabled") as? Bool {
                    canonical["disabled"] = !enabled
                }
                return canonical
            }
        }
    }

    /// The editor owns transport fields only; native OAuth, timeouts, enablement and extensions must survive an edit.
    static func mergingEdit(_ edited: RawServerEntry, into existing: RawServerEntry, type: MCPAdapterType) -> RawServerEntry {
        guard type == .opencode else { return edited }
        let editableKeys: Set<String> = ["type", "command", "url", "headers", "environment"]
        return existing.filter { !editableKeys.contains($0.key) }.merging(edited) { _, new in new }
    }
}
