import AppKit
import ImageIO

/// Loads and caches GitHub avatar images in memory, deduplicating concurrent
/// requests for the same URL. Avatars are small (64px) so the cache is unbounded
/// for the app's lifetime.
///
/// Main-actor rather than an `actor` so a list row can read an already-loaded avatar
/// *synchronously* from `body`. A row that scrolls out of a `LazyVStack` loses its view state,
/// so with an `await`-only API scrolling back in re-spawned a task, hopped actors, and wrote
/// `@State` — a second render and layout pass per row, landing exactly when a fast scroll has
/// the main actor busiest. Only the dictionary lookups are main-actor; both the fetch and the
/// decode stay off it inside `loadImage(from:session:)`.
@MainActor
final class GitHubAvatarLoader {
    private let session: URLSession
    private var cache: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    /// `nonisolated` so the app-scoped DI provider and tests can build one from any context; it
    /// only initializes stored properties.
    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    /// The already-loaded avatar, or `nil` when one still has to be fetched.
    ///
    /// Synchronous by design: it lets a warm row draw its avatar on its first `body` pass with no
    /// task, no suspension, and no frame showing the letter placeholder. Deliberately *not*
    /// observable — a list re-rendering every time some other row's avatar landed is the cost this
    /// whole type exists to avoid.
    func cachedImage(for url: URL) -> NSImage? {
        cache[url]
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        if let pending = inFlight[url] {
            return await pending.value
        }
        // Check-then-insert with no suspension between them, so two callers racing for the same
        // URL on the main actor cannot both start a fetch.
        let load = Task.detached(priority: .userInitiated) { [session] in
            await Self.loadImage(from: url, session: session)
        }
        inFlight[url] = load
        let image = await load.value
        inFlight[url] = nil
        if let image {
            cache[url] = image
        }
        return image
    }

    /// Warms the cache for rows the reader has not scrolled to yet, so the first flick through a
    /// freshly loaded list draws avatars instead of letter placeholders. Already-cached and
    /// in-flight URLs are skipped, and duplicates within one call collapse — a list routinely
    /// repeats an author across rows.
    func prefetch(_ urls: some Sequence<URL>) {
        var requested: Set<URL> = []
        for url in urls where cache[url] == nil && inFlight[url] == nil && requested.insert(url).inserted {
            Task { _ = await image(for: url) }
        }
    }

    /// `nonisolated` so the fetch and the decode both run off the main actor.
    private nonisolated static func loadImage(from url: URL, session: URLSession) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url) else {
            return nil
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            return nil
        }
        return decodedImage(from: data)
    }

    /// `NSImage(data:)` keeps the compressed bytes and defers the decode to first draw — which
    /// happens on the main thread. A fast scroll past hundreds of rows would then pay a decode on
    /// each frame that first draws one, so rasterize here and hand back a draw-ready bitmap.
    private nonisolated static func decodedImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
