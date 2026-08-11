import AppKit

/// Loads and caches GitHub avatar images in memory, deduplicating concurrent
/// requests for the same URL. Avatars are small (64px) so the cache is unbounded
/// for the app's lifetime.
actor GitHubAvatarLoader {
    private let session: URLSession
    private var cache: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        if let pending = inFlight[url] {
            return await pending.value
        }
        let load = Task<NSImage?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url) else {
                return nil
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                return nil
            }
            return NSImage(data: data)
        }
        inFlight[url] = load
        let image = await load.value
        inFlight[url] = nil
        if let image {
            cache[url] = image
        }
        return image
    }
}
