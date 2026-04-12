import Foundation

actor DefaultSessionManager: SessionManager {
    private var entries: [String: SessionEntry] = [:]
    private let fileURL: URL
    private var hasLoaded = false

    init(supportDirectory: URL) {
        self.fileURL = supportDirectory.appendingPathComponent("session-map.json")
    }

    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool {
        ensureLoaded()

        let normalizedCWD = CanonicalPath.normalize(cwd)
        let shouldPreserveIdentity: Bool
        let sessionId: String

        if let existing = entries[conversationId] {
            shouldPreserveIdentity = existing.cwd == normalizedCWD && existing.providerId == providerId
            sessionId = shouldPreserveIdentity ? existing.appSessionId : UUID().uuidString
        } else {
            shouldPreserveIdentity = false
            sessionId = UUID().uuidString
        }

        entries[conversationId] = SessionEntry(
            cwd: normalizedCWD,
            providerId: providerId,
            appSessionId: sessionId,
            launchSessionId: sessionId
        )
        persistIgnoringFailure(prefix: shouldPreserveIdentity ? "reconciled" : "new")
        return shouldPreserveIdentity
    }

    func removeEntry(for conversationId: String) throws {
        ensureLoaded()
        entries.removeValue(forKey: conversationId)
        try persist()
    }

    func hasSession(for conversationId: String) -> Bool {
        ensureLoaded()
        return entries[conversationId] != nil
    }

    func sessionId(for conversationId: String) -> String {
        ensureLoaded()
        guard let entry = entries[conversationId] else {
            preconditionFailure("sessionId(for:) requires an existing entry; call createEntry() first")
        }
        return entry.appSessionId
    }

    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String? {
        ensureLoaded()
        let normalizedCWD = CanonicalPath.normalize(cwd)
        return entries.first { _, entry in
            (entry.appSessionId == sessionId || entry.launchSessionId == sessionId) &&
                entry.cwd == normalizedCWD &&
                entry.providerId == providerId
        }?.key
    }

    func updateSessionId(for conversationId: String, newSessionId: String) throws {
        ensureLoaded()
        guard entries[conversationId] != nil else {
            return
        }
        entries[conversationId]?.appSessionId = newSessionId
        try persist()
    }

    func load() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }

        do {
            entries = try JSONDecoder().decode([String: SessionEntry].self, from: data)
        } catch {
            let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("session-map.corrupt.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            print("[SessionManager] Corrupted session map backed up to \(backupURL.path): \(error)")
        }
    }

    func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureLoaded() {
        guard !hasLoaded else {
            return
        }
        load()
    }

    private func persistIgnoringFailure(prefix: String) {
        do {
            try persist()
        } catch {
            print("[SessionManager] Failed to persist \(prefix) session binding: \(error)")
        }
    }
}
