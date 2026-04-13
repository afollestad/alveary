import Foundation

struct AlvearyProjectConfig: Sendable, Equatable {
    var setupScript: String?
    var setupTimeoutSeconds: Int?
    var teardownScript: String?
    var shellSetup: String?
    var preservePatterns: [String]?
    var actions: [ProjectAction]?

    struct ProjectAction: Sendable, Equatable {
        var icon: String?
        var name: String
        var command: String

        init(icon: String? = nil, name: String, command: String) {
            self.icon = icon
            self.name = name
            self.command = command
        }
    }

    static let empty = Self()

    init(
        setupScript: String? = nil,
        setupTimeoutSeconds: Int? = nil,
        teardownScript: String? = nil,
        shellSetup: String? = nil,
        preservePatterns: [String]? = nil,
        actions: [ProjectAction]? = nil
    ) {
        self.setupScript = setupScript
        self.setupTimeoutSeconds = setupTimeoutSeconds
        self.teardownScript = teardownScript
        self.shellSetup = shellSetup
        self.preservePatterns = preservePatterns
        self.actions = actions
    }

    init(projectPath: String) async {
        let configURL = URL(fileURLWithPath: projectPath).appendingPathComponent(".alveary.json")
        let data = await Self.loadData(from: configURL)

        self.init(data: data)
    }

    private init(data: Data?) {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            self = .empty
            return
        }

        let scripts = json["scripts"] as? [String: Any]
        setupScript = Self.normalizedString(scripts?["setup"] as? String)
        setupTimeoutSeconds = (scripts?["setupTimeoutSeconds"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        teardownScript = Self.normalizedString(scripts?["teardown"] as? String)
        shellSetup = Self.normalizedString(json["shellSetup"] as? String)
        preservePatterns = Self.normalizedPatterns(json["preservePatterns"] as? [String])
        actions = (json["actions"] as? [[String: Any]])?.compactMap { action in
            guard let name = Self.normalizedString(action["name"] as? String),
                  let command = Self.normalizedString(action["command"] as? String) else {
                return nil
            }

            return ProjectAction(
                icon: Self.normalizedString(action["icon"] as? String),
                name: name,
                command: command
            )
        }
    }

    func updatingEditableFields(
        setupScript: String,
        teardownScript: String,
        preservePatterns: [String],
        actions: [ProjectAction]
    ) -> Self {
        var updated = self
        updated.setupScript = Self.normalizedString(setupScript)
        updated.teardownScript = Self.normalizedString(teardownScript)
        updated.preservePatterns = Self.normalizedPatterns(preservePatterns)
        updated.actions = Self.normalizedActions(actions)
        return updated
    }

    func write(projectPath: String) async throws {
        let configURL = URL(fileURLWithPath: projectPath).appendingPathComponent(".alveary.json")
        let data = try Self.serializedData(for: self)

        try await Task.detached(priority: .utility) {
            try data.write(to: configURL, options: .atomic)
        }.value
    }

    private static func loadData(from configURL: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: configURL)
        }.value
    }

    private static func serializedData(for config: Self) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: config.normalizedForPersistence.jsonObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(0x0A)
        return data
    }

    private var normalizedForPersistence: Self {
        updatingEditableFields(
            setupScript: setupScript ?? "",
            teardownScript: teardownScript ?? "",
            preservePatterns: preservePatterns ?? [],
            actions: actions ?? []
        )
    }

    private var jsonObject: [String: Any] {
        var json: [String: Any] = [:]
        var scripts: [String: Any] = [:]

        if let setupScript {
            scripts["setup"] = setupScript
        }
        if let setupTimeoutSeconds {
            scripts["setupTimeoutSeconds"] = setupTimeoutSeconds
        }
        if let teardownScript {
            scripts["teardown"] = teardownScript
        }
        if !scripts.isEmpty {
            json["scripts"] = scripts
        }

        if let shellSetup {
            json["shellSetup"] = shellSetup
        }
        if let preservePatterns {
            json["preservePatterns"] = preservePatterns
        }
        if let actions {
            json["actions"] = actions.map { action in
                var jsonAction: [String: Any] = [
                    "name": action.name,
                    "command": action.command
                ]
                if let icon = Self.normalizedString(action.icon) {
                    jsonAction["icon"] = icon
                }
                return jsonAction
            }
        }

        return json
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedPatterns(_ patterns: [String]?) -> [String]? {
        guard let patterns else {
            return nil
        }

        let normalized = patterns.compactMap(normalizedString)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedActions(_ actions: [ProjectAction]?) -> [ProjectAction]? {
        guard let actions else {
            return nil
        }

        let normalized = actions.compactMap { action -> ProjectAction? in
            guard let name = normalizedString(action.name),
                  let command = normalizedString(action.command) else {
                return nil
            }

            return ProjectAction(
                icon: normalizedString(action.icon),
                name: name,
                command: command
            )
        }

        return normalized.isEmpty ? nil : normalized
    }
}
