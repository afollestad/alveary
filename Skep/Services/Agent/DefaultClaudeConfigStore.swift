import Foundation

actor DefaultClaudeConfigStore: ClaudeConfigStore {
    private let homeDirectoryURL: URL

    init(homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        self.homeDirectoryURL = homeDirectoryURL
    }

    func ensureLocalSettingsFile(in workingDirectory: String) async {
        let settingsURL = localSettingsURL(in: workingDirectory)
        guard !FileManager.default.fileExists(atPath: settingsURL.path) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try Data("{}".utf8).write(to: settingsURL, options: .atomic)
        } catch {
            print("[ClaudeConfigStore] Failed to create local settings file at \(settingsURL.path): \(error)")
        }
    }

    func upsertTrustedProject(path: String) async {
        let normalizedPath = CanonicalPath.normalize(path)
        var root = readGlobalConfig()
        var projects = root[GlobalConfigKey.projects] as? [String: Any] ?? [:]
        var project = projects[normalizedPath] as? [String: Any] ?? [:]
        project[TrustedProjectKey.hasTrustDialogAccepted] = true
        project[TrustedProjectKey.hasCompletedProjectOnboarding] = true
        projects[normalizedPath] = project
        root[GlobalConfigKey.projects] = projects

        do {
            try writeGlobalConfig(root)
        } catch {
            print("[ClaudeConfigStore] Failed to update trusted project entry for \(normalizedPath): \(error)")
        }
    }

    func readMCPServers() async -> [String: ClaudeMCPServerConfig] {
        let root = readGlobalConfig()
        guard let serverObject = root[GlobalConfigKey.mcpServers] as? [String: Any] else {
            return [:]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: serverObject),
              let servers = try? JSONDecoder().decode([String: ClaudeMCPServerConfig].self, from: data) else {
            return [:]
        }
        return servers
    }

    func writeMCPServers(_ servers: [String: ClaudeMCPServerConfig]) async {
        do {
            guard let serverObject = try encodeJSONObject(servers) as? [String: Any] else {
                print("[ClaudeConfigStore] Failed to encode MCP servers payload")
                return
            }

            var root = readGlobalConfig()
            root[GlobalConfigKey.mcpServers] = serverObject
            try writeGlobalConfig(root)
        } catch {
            print("[ClaudeConfigStore] Failed to write MCP servers: \(error)")
        }
    }
}

private extension DefaultClaudeConfigStore {
    enum GlobalConfigKey {
        static let projects = "projects"
        static let mcpServers = "mcpServers"
    }

    enum TrustedProjectKey {
        static let hasTrustDialogAccepted = "hasTrustDialogAccepted"
        static let hasCompletedProjectOnboarding = "hasCompletedProjectOnboarding"
    }

    var globalConfigURL: URL {
        homeDirectoryURL.appendingPathComponent(".claude.json")
    }

    func localSettingsURL(in workingDirectory: String) -> URL {
        URL(fileURLWithPath: CanonicalPath.normalize(workingDirectory), isDirectory: true)
            .appendingPathComponent(".claude/settings.local.json")
    }

    func readGlobalConfig() -> [String: Any] {
        guard let data = try? Data(contentsOf: globalConfigURL), !data.isEmpty else {
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ClaudeConfigStore] Failed to parse global config at \(globalConfigURL.path); treating it as empty")
            return [:]
        }
        return object
    }

    func writeGlobalConfig(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: globalConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        if data.last != 0x0A {
            data.append(0x0A)
        }

        let tempURL = globalConfigURL
            .deletingLastPathComponent()
            .appendingPathComponent(".claude-config-\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)

        do {
            if FileManager.default.fileExists(atPath: globalConfigURL.path) {
                try FileManager.default.replaceItemAt(
                    globalConfigURL,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: tempURL, to: globalConfigURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    func encodeJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
