import Foundation

/// One in-memory copy of each project's `.alveary.json`, shared by every surface that
/// reads it.
///
/// Selecting a project row mounts the settings editor and loads the toolbar's project
/// actions on the same frame, and both want the same file. Going through here means
/// one read instead of two, and a project visited earlier renders populated on the
/// selection frame rather than blanking while a fresh read lands.
///
/// This is a cache, not a watcher: it learns about changes the app itself makes.
/// Surfaces that must see an outside edit call `reload(forProjectPath:)`.
@MainActor
final class ProjectConfigStore {
    static let shared = ProjectConfigStore()

    private var writeRevisions: [String: UInt64] = [:]
    private var configs: [String: AlvearyProjectConfig] = [:]
    private var inFlightLoads: [String: Task<AlvearyProjectConfig, Never>] = [:]
    private var pendingWrites: [String: (id: UUID, task: Task<Void, Error>)] = [:]
    private let writeConfig: (AlvearyProjectConfig, String) async throws -> Void
    private let read: (String) async -> AlvearyProjectConfig

    convenience init(read: @escaping (String) async -> AlvearyProjectConfig = { path in
        await AlvearyProjectConfig(projectPath: path)
    }) {
        self.init(write: { config, path in try await config.write(projectPath: path) }, read: read)
    }

    init(
        write: @escaping (AlvearyProjectConfig, String) async throws -> Void,
        read: @escaping (String) async -> AlvearyProjectConfig = { path in
            await AlvearyProjectConfig(projectPath: path)
        }
    ) {
        self.read = read
        self.writeConfig = write
    }

    /// Serializes same-folder writes across windows. Cancelling a view's debounce cannot let an
    /// older atomic disk write finish after a newer one and replace the user's latest changes.
    func write(_ config: AlvearyProjectConfig, forProjectPath path: String) async throws {
        let predecessor = pendingWrites[path]?.task
        let id = UUID()
        let task = Task { @MainActor in
            _ = try? await predecessor?.value
            try await writeConfig(config, path)
            store(config, forProjectPath: path)
        }
        pendingWrites[path] = (id, task)
        defer { if pendingWrites[path]?.id == id { pendingWrites[path] = nil } }
        try await task.value
    }

    /// An already-loaded config, without touching the filesystem. Seed a view's initial
    /// state from this so a revisited project renders populated instead of empty.
    func cached(forProjectPath path: String) -> AlvearyProjectConfig? {
        configs[path]
    }

    /// The cached config when there is one, otherwise a read.
    func config(forProjectPath path: String) async -> AlvearyProjectConfig {
        if let cached = configs[path] {
            return cached
        }
        return await reload(forProjectPath: path)
    }

    /// Reads from disk even when a value is cached, so an edit made outside the app
    /// still reaches the surface that asked. Callers arriving while a read is already
    /// running share it rather than starting a second one.
    @discardableResult
    func reload(forProjectPath path: String) async -> AlvearyProjectConfig {
        if let inFlight = inFlightLoads[path] {
            return await inFlight.value
        }

        let revision = writeRevisions[path, default: 0]
        let task = Task { @MainActor in
            let config = await read(path)
            // Cleared before the value is published so a caller resuming on the change
            // notification starts a fresh read rather than joining this finished one.
            inFlightLoads[path] = nil
            guard writeRevisions[path, default: 0] == revision else {
                return configs[path] ?? config
            }
            apply(config, forProjectPath: path)
            return config
        }
        inFlightLoads[path] = task
        return await task.value
    }

    /// Records a config the app just wrote, so nothing re-reads what it already has.
    func store(_ config: AlvearyProjectConfig, forProjectPath path: String) {
        writeRevisions[path, default: 0] &+= 1
        apply(config, forProjectPath: path)
    }

    /// Announces a replaced value so surfaces holding the old one can catch up. A first
    /// load announces nothing — no reader can be stale yet.
    private func apply(_ config: AlvearyProjectConfig, forProjectPath path: String) {
        let previous = configs[path]
        configs[path] = config

        guard let previous, previous != config else {
            return
        }
        ProjectConfigChangeNotifier.post(projectPath: path)
    }
}
