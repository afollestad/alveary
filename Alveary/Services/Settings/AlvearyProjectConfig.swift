import Foundation

struct AlvearyProjectConfig: Sendable, Equatable {
    let setupScript: String?
    let setupTimeoutSeconds: Int?
    let teardownScript: String?
    let shellSetup: String?
    let preservePatterns: [String]?
    let actions: [ProjectAction]?

    struct ProjectAction: Sendable, Equatable {
        let name: String
        let command: String
    }

    init(projectPath: String) async {
        let configURL = URL(fileURLWithPath: projectPath).appendingPathComponent(".alveary.json")
        let data = await Self.loadData(from: configURL)

        self.init(data: data)
    }

    private init(data: Data?) {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            setupScript = nil
            setupTimeoutSeconds = nil
            teardownScript = nil
            shellSetup = nil
            preservePatterns = nil
            actions = nil
            return
        }

        let scripts = json["scripts"] as? [String: Any]
        setupScript = (scripts?["setup"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        setupTimeoutSeconds = (scripts?["setupTimeoutSeconds"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        teardownScript = (scripts?["teardown"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        shellSetup = (json["shellSetup"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        preservePatterns = json["preservePatterns"] as? [String]
        actions = (json["actions"] as? [[String: Any]])?.compactMap { action in
            guard let name = action["name"] as? String,
                  let command = action["command"] as? String else {
                return nil
            }

            return ProjectAction(name: name, command: command)
        }
    }

    private static func loadData(from configURL: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: configURL)
        }.value
    }
}
