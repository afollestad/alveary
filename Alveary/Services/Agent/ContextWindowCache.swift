import Foundation

struct ContextWindowCacheEntry: Codable, Equatable, Sendable {
    let contextWindowSize: Int
    let updatedAt: Date
}

protocol ContextWindowCache: Sendable {
    func contextWindowSize(providerId: String, model: String) async -> Int?
    func update(
        providerId: String,
        selectedModel: String,
        reportedModelId: String?,
        contextWindowSize: Int
    ) async
}

actor JSONContextWindowCache: ContextWindowCache {
    private let fileURL: URL
    private let fileManager: FileManager
    private var entries: [String: ContextWindowCacheEntry]?

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.fileManager = fileManager
    }

    func contextWindowSize(providerId: String, model: String) async -> Int? {
        guard let key = Self.cacheKey(providerId: providerId, model: model) else {
            return nil
        }
        return loadEntries()[key]?.contextWindowSize
    }

    func update(
        providerId: String,
        selectedModel: String,
        reportedModelId: String?,
        contextWindowSize: Int
    ) async {
        guard contextWindowSize > 0 else {
            return
        }

        var keys = Set<String>()
        if let selectedKey = Self.cacheKey(providerId: providerId, model: selectedModel) {
            keys.insert(selectedKey)
        }
        if let reportedModelId,
           let reportedKey = Self.cacheKey(providerId: providerId, model: reportedModelId) {
            keys.insert(reportedKey)
        }
        guard !keys.isEmpty else {
            return
        }

        var currentEntries = loadEntries()
        let entry = ContextWindowCacheEntry(contextWindowSize: contextWindowSize, updatedAt: .now)
        var didChange = false
        for key in keys where currentEntries[key]?.contextWindowSize != contextWindowSize {
            currentEntries[key] = entry
            didChange = true
        }

        guard didChange else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder.contextWindowCacheEncoder.encode(currentEntries)
            try data.write(to: fileURL, options: .atomic)
            entries = currentEntries
        } catch {
            // Cache writes are best-effort; provider-reported result data remains authoritative.
        }
    }

    static func cacheKey(providerId: String, model: String) -> String? {
        let provider = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !provider.isEmpty, !model.isEmpty else {
            return nil
        }
        return "\(provider):\(model)"
    }

    private func loadEntries() -> [String: ContextWindowCacheEntry] {
        if let entries {
            return entries
        }

        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.contextWindowCacheDecoder.decode(
                  [String: ContextWindowCacheEntry].self,
                  from: data
              ) else {
            entries = [:]
            return [:]
        }
        entries = decoded
        return decoded
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("ContextWindows", isDirectory: true)
            .appendingPathComponent("context-window-sizes.json")
    }
}

private extension JSONEncoder {
    static var contextWindowCacheEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var contextWindowCacheDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
