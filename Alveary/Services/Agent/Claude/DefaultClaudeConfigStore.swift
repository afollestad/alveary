import Darwin
import Foundation

actor DefaultClaudeConfigStore: ClaudeConfigStore {
    private let homeDirectoryURL: URL
    private let snapshotCache: ClaudeConfigSnapshotCache
    private var fileObserver: ClaudeConfigFileObserver?
    private var cachedRoot: [String: Any]
    private var lastObservedCanonicalJSON: String
    private var snapshotContinuations: [UUID: AsyncStream<ClaudeConfigSnapshot>.Continuation] = [:]
    private var revision = 0

    init(homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        self.homeDirectoryURL = homeDirectoryURL
        let globalConfigURL = homeDirectoryURL.appendingPathComponent(".claude.json")
        let root = Self.readGlobalConfig(at: globalConfigURL)
        let snapshot = Self.makeSnapshot(from: root, revision: 0)
        self.cachedRoot = root
        self.snapshotCache = ClaudeConfigSnapshotCache(snapshot: snapshot)
        self.lastObservedCanonicalJSON = Self.canonicalJSONString(from: root)
        self.fileObserver = nil
    }

    nonisolated func cachedSnapshot() -> ClaudeConfigSnapshot {
        snapshotCache.snapshot
    }

    func currentSnapshot() async -> ClaudeConfigSnapshot {
        startObservingIfNeeded()
        refreshCacheIfNeeded()
        return snapshotCache.snapshot
    }

    func snapshots() async -> AsyncStream<ClaudeConfigSnapshot> {
        startObservingIfNeeded()
        let snapshot = snapshotCache.snapshot
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeSnapshotContinuation(id: id)
                }
            }
            snapshotContinuations[id] = continuation
        }
    }

    func isTrustedProject(path: String) async -> Bool {
        startObservingIfNeeded()
        refreshCacheIfNeeded()
        return snapshotCache.snapshot.isTrustedProject(path: path)
    }

    func upsertTrustedProject(path: String) async {
        startObservingIfNeeded()
        refreshCacheIfNeeded()
        let normalizedPath = CanonicalPath.normalize(path)
        var root = cachedRoot
        var projects = root[GlobalConfigKey.projects] as? [String: Any] ?? [:]
        var project = projects[normalizedPath] as? [String: Any] ?? [:]
        project[TrustedProjectKey.hasTrustDialogAccepted] = true
        project[TrustedProjectKey.hasCompletedProjectOnboarding] = true
        projects[normalizedPath] = project
        root[GlobalConfigKey.projects] = projects

        do {
            try writeGlobalConfig(root)
            refreshCacheIfNeeded(root: root)
        } catch {
            print("[ClaudeConfigStore] Failed to update trusted project entry for \(normalizedPath): \(error)")
        }
    }

    func readMCPServers() async -> [String: ClaudeMCPServerConfig] {
        startObservingIfNeeded()
        refreshCacheIfNeeded()
        guard let serverObject = cachedRoot[GlobalConfigKey.mcpServers] as? [String: Any] else {
            return [:]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: serverObject),
              let servers = try? JSONDecoder().decode([String: ClaudeMCPServerConfig].self, from: data) else {
            return [:]
        }
        return servers
    }

    func writeMCPServers(_ servers: [String: ClaudeMCPServerConfig]) async {
        startObservingIfNeeded()
        refreshCacheIfNeeded()
        do {
            guard let serverObject = try encodeJSONObject(servers) as? [String: Any] else {
                print("[ClaudeConfigStore] Failed to encode MCP servers payload")
                return
            }

            var root = cachedRoot
            root[GlobalConfigKey.mcpServers] = serverObject
            try writeGlobalConfig(root)
            refreshCacheIfNeeded(root: root)
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

    func startObservingIfNeeded() {
        guard fileObserver == nil else {
            return
        }

        fileObserver = ClaudeConfigFileObserver(configURL: globalConfigURL) { [weak self] in
            Task {
                await self?.refreshCacheIfNeeded()
            }
        }
    }

    func readGlobalConfig() -> [String: Any] {
        Self.readGlobalConfig(at: globalConfigURL)
    }

    static func readGlobalConfig(at globalConfigURL: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: globalConfigURL), !data.isEmpty else {
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ClaudeConfigStore] Failed to parse global config at \(globalConfigURL.path); treating it as empty")
            return [:]
        }
        return object
    }

    static func makeSnapshot(from root: [String: Any], revision: Int) -> ClaudeConfigSnapshot {
        let trustedProjectPaths = trustedProjectPaths(from: root)
        return ClaudeConfigSnapshot(revision: revision, trustedProjectPaths: trustedProjectPaths)
    }

    static func trustedProjectPaths(from root: [String: Any]) -> Set<String> {
        guard let projects = root[GlobalConfigKey.projects] as? [String: Any] else {
            return []
        }

        return Set(projects.compactMap { path, value in
            guard isTrustedProjectObject(value) else {
                return nil
            }
            return CanonicalPath.normalize(path)
        })
    }

    static func isTrustedProjectObject(_ value: Any) -> Bool {
        guard let project = value as? [String: Any] else {
            return false
        }

        return project[TrustedProjectKey.hasTrustDialogAccepted] as? Bool == true &&
            project[TrustedProjectKey.hasCompletedProjectOnboarding] as? Bool == true
    }

    @discardableResult
    func refreshCacheIfNeeded(root: [String: Any]? = nil) -> Bool {
        let root = root ?? readGlobalConfig()
        let canonicalJSON = Self.canonicalJSONString(from: root)
        guard canonicalJSON != lastObservedCanonicalJSON else {
            cachedRoot = root
            return false
        }

        lastObservedCanonicalJSON = canonicalJSON
        revision += 1
        cachedRoot = root
        let snapshot = Self.makeSnapshot(from: root, revision: revision)
        snapshotCache.update(snapshot)
        snapshotContinuations.values.forEach { continuation in
            continuation.yield(snapshot)
        }
        NotificationCenter.default.post(
            name: .claudeConfigChanged,
            object: self,
            userInfo: [ClaudeConfigNotificationKey.snapshot: snapshot]
        )
        return true
    }

    func removeSnapshotContinuation(id: UUID) {
        snapshotContinuations[id] = nil
    }

    static func canonicalJSONString(from root: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    func writeGlobalConfig(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: globalConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if data.last != 0x0A {
            data.append(0x0A)
        }

        let tempURL = globalConfigURL
            .deletingLastPathComponent()
            .appendingPathComponent(".claude-config-\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)

        do {
            if FileManager.default.fileExists(atPath: globalConfigURL.path) {
                _ = try FileManager.default.replaceItemAt(
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

private final class ClaudeConfigSnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: ClaudeConfigSnapshot

    init(snapshot: ClaudeConfigSnapshot) {
        self.storedSnapshot = snapshot
    }

    var snapshot: ClaudeConfigSnapshot {
        lock.withLock {
            storedSnapshot
        }
    }

    func update(_ snapshot: ClaudeConfigSnapshot) {
        lock.withLock {
            storedSnapshot = snapshot
        }
    }
}

private final class ClaudeConfigFileObserver: @unchecked Sendable {
    private let configURL: URL
    private let queue = DispatchQueue(label: "com.alveary.claude-config-observer")
    private let onChange: @Sendable () -> Void
    private var directoryDescriptor: CInt = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var fileSource: DispatchSourceFileSystemObject?

    init?(configURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.configURL = configURL
        self.onChange = onChange
        let directoryURL = configURL.deletingLastPathComponent()
        directoryDescriptor = open(directoryURL.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            return nil
        }

        let directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        directorySource.setEventHandler { [weak self] in
            self?.refreshFileSource()
            onChange()
        }
        directorySource.setCancelHandler { [directoryDescriptor] in
            close(directoryDescriptor)
        }
        directorySource.resume()
        self.directorySource = directorySource

        refreshFileSource()
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
    }

    private func refreshFileSource() {
        guard fileSource == nil,
              FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }

        fileDescriptor = open(configURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        fileSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let event = self.fileSource?.data ?? []
            if event.contains(.delete) || event.contains(.rename) {
                self.fileSource?.cancel()
                self.fileSource = nil
                self.refreshFileSource()
            }
            onChange()
        }
        fileSource.setCancelHandler { [descriptor = fileDescriptor] in
            close(descriptor)
        }
        fileSource.resume()
        self.fileSource = fileSource
    }
}
