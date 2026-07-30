import AppKit
import BlockInputKit
import ImageIO
import Observation

/// App-wide cache and loader for markdown images rendered by the SwiftUI and
/// AppKit renderers. One store serves every surface so repeated sources (badge
/// URLs, comment screenshots) load once; observation lets SwiftUI views refresh
/// when a bitmap arrives.
@MainActor
@Observable
final class AppMarkdownImageStore {
    static let shared = AppMarkdownImageStore()

    enum ImageState {
        case loading
        case loaded(NSImage)
        case failed(Date)
    }

    private(set) var states: [String: ImageState] = [:]

    /// Consulted when a remote load fails: may mint an alternate URL for the
    /// same content (e.g. a signed GitHub attachment URL) to retry once, still
    /// cached under the original source's key. App setup wires this to
    /// `GitHubAttachmentImageURLResolver`.
    @ObservationIgnored var remoteFallbackURLProvider: (@MainActor (String) async -> URL?)?

    @ObservationIgnored private let loader: any BlockInputImageLoading
    @ObservationIgnored private let diskCache: (any BlockInputImageDiskCaching)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryContexts: [String: FailedLoadRetryContext] = [:]

    private static let maximumSourceBytes = 20 * 1024 * 1024
    private static let maximumPixelDimension = 8_192
    /// How long a failure sticks before `ensureLoad` may try again. Fresh GitHub
    /// attachments 404 until their embedding content is saved and propagated, so
    /// a permanent per-launch failure left images broken until relaunch.
    private static let failureRetryInterval: TimeInterval = 30
    /// Self-driven retries after a failure, so a visible broken image heals
    /// without waiting for the next render to call `ensureLoad`.
    private static let maximumAutomaticRetries = 2

    init(
        loader: any BlockInputImageLoading = BlockInputDefaultImageLoader(),
        diskCache: (any BlockInputImageDiskCaching)? = BlockInputDefaultImageDiskCache(),
        now: @escaping () -> Date = Date.init
    ) {
        self.loader = loader
        self.diskCache = diskCache
        self.now = now
    }

    func image(forSource source: String) -> NSImage? {
        guard case let .loaded(image) = states[source] else {
            return nil
        }
        return image
    }

    func hasFailed(source: String) -> Bool {
        guard case .failed = states[source] else {
            return false
        }
        return true
    }

    /// Seeds a locally known bitmap for a remote source — the file the app just
    /// uploaded — so every renderer (markdown store, BlockInputKit editors, the
    /// preview modal) shows it immediately and future launches hit the shared
    /// disk cache. GitHub keeps fresh attachment assets session-gated until the
    /// embedding content is saved and propagated, so without the seed the
    /// uploader's own image renders as a failure.
    func seedRemoteImage(source: String, fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL),
              data.count <= Self.maximumSourceBytes,
              let nsImage = NSImage(data: data),
              nsImage.size.width > 0,
              nsImage.size.height > 0 else {
            return
        }
        loadTasks[source]?.cancel()
        loadTasks[source] = nil
        cancelAutomaticRetry(for: source)
        states[source] = .loaded(nsImage)
        postStateChange(for: source)

        // Every consumer derives the same key (`default-v1|url|8192`) and the
        // default disk caches share one directory, so this single write also
        // serves the BlockInputKit editors and the image preview modal.
        guard let diskCache, let resolvedURL = URL(string: source) else {
            return
        }
        let key = BlockInputImage(source: source).cacheKey(
            resolvedURL: resolvedURL,
            maximumPixelDimension: Self.maximumPixelDimension
        )
        let entry = BlockInputImageDiskCacheEntry(
            data: data,
            dimensions: Self.imageDimensions(from: data, fallbackImage: nsImage)
        )
        try? await diskCache.storeImage(entry, forKey: key)
    }

    /// Starts a load unless one already finished or is in flight. Keyed by the
    /// raw source string; callers resolve relative sources before asking. A
    /// failed source becomes loadable again after `failureRetryInterval` — a
    /// remote image that 404s can start existing later (GitHub attachments stay
    /// session-gated until their embedding content is saved).
    func ensureLoad(for image: BlockInputImage, baseURL: URL?) {
        let source = image.source
        guard shouldAttemptLoad(of: source) else {
            return
        }
        guard let resolvedURL = AppMarkdownImageSourceResolver.resolvedURL(for: source, baseURL: baseURL) else {
            // Unresolvable sources are permanent failures; a retry cannot help.
            states[source] = .failed(.distantFuture)
            return
        }
        states[source] = .loading
        let request = BlockInputImageLoadRequest(
            image: image,
            resolvedURL: resolvedURL,
            cacheKey: image.cacheKey(resolvedURL: resolvedURL, maximumPixelDimension: Self.maximumPixelDimension),
            maxSourceBytes: Self.maximumSourceBytes,
            maxPixelDimension: Self.maximumPixelDimension,
            diskCache: diskCache
        )
        loadTasks[source] = makeLoadTask(request: request, image: image, baseURL: baseURL)
    }

    private func shouldAttemptLoad(of source: String) -> Bool {
        switch states[source] {
        case .loading, .loaded:
            return false
        case .failed(let failedAt):
            return now().timeIntervalSince(failedAt) >= Self.failureRetryInterval
        case .none:
            return true
        }
    }

    private func makeLoadTask(
        request: BlockInputImageLoadRequest,
        image: BlockInputImage,
        baseURL: URL?
    ) -> Task<Void, Never> {
        let source = image.source
        let loader = loader
        return Task { [weak self] in
            do {
                let loaded = try await loader.loadImage(request)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoad(loaded, source: source)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if let fallbackLoaded = await self?.loadThroughFallbackURL(request: request, source: source) {
                    await MainActor.run {
                        self?.finishLoad(fallbackLoaded, source: source)
                    }
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoadFailure(source: source, image: image, baseURL: baseURL)
                }
            }
        }
    }

    /// Retries a failed remote load through a minted alternate URL — same cache
    /// key, so the bytes persist under the original source for future launches.
    private func loadThroughFallbackURL(
        request: BlockInputImageLoadRequest,
        source: String
    ) async -> BlockInputLoadedImage? {
        guard !request.resolvedURL.isFileURL,
              let fallbackURL = await remoteFallbackURLProvider?(source),
              fallbackURL != request.resolvedURL else {
            return nil
        }
        var fallbackRequest = request
        fallbackRequest.resolvedURL = fallbackURL
        return try? await loader.loadImage(fallbackRequest)
    }

    /// Seeds a loaded bitmap so snapshot hosts and tests render deterministically.
    func preloadForTesting(source: String, image: NSImage) {
        states[source] = .loaded(image)
    }

    /// Compact digest of this store's load states for every image source in the
    /// markdown. Measurement caches must include it in their keys: an inline
    /// image growing from alt text to a bitmap changes measured heights, and a
    /// key without the digest would keep returning the pre-load measurement.
    func loadStateFingerprint(forMarkdown markdown: String) -> String {
        guard markdown.contains("![") || markdown.range(of: "<img", options: .caseInsensitive) != nil else {
            return ""
        }
        return AppMarkdownImageSyntaxParser.imageMatchesOutsideCode(in: markdown)
            .map { match in
                switch states[match.image.source] {
                case .none:
                    return "n"
                case .loading:
                    return "p"
                case .failed:
                    return "f"
                case .loaded(let image):
                    return "l\(Int(image.size.width))x\(Int(image.size.height))"
                }
            }
            .joined(separator: ",")
    }

    private func finishLoad(_ loaded: BlockInputLoadedImage, source: String) {
        loadTasks[source] = nil
        guard let nsImage = NSImage(data: loaded.data), nsImage.size.width > 0, nsImage.size.height > 0 else {
            finishLoadFailure(source: source, image: nil, baseURL: nil)
            return
        }
        cancelAutomaticRetry(for: source)
        states[source] = .loaded(nsImage)
        postStateChange(for: source)
    }

    private func cancelAutomaticRetry(for source: String) {
        retryContexts[source]?.task.cancel()
        retryContexts[source] = nil
    }

    private func finishLoadFailure(source: String, image: BlockInputImage?, baseURL: URL?) {
        loadTasks[source] = nil
        states[source] = .failed(now())
        postStateChange(for: source)
        if let image {
            scheduleAutomaticRetry(for: image, baseURL: baseURL)
        }
    }

    /// A visible failure block re-renders only when something else invalidates
    /// it, so `ensureLoad`'s retry window alone leaves a broken image broken on
    /// an untouched screen. A couple of self-driven retries heal it in place.
    private func scheduleAutomaticRetry(for image: BlockInputImage, baseURL: URL?) {
        let source = image.source
        let attempts = retryContexts[source]?.attempts ?? 0
        guard attempts < Self.maximumAutomaticRetries else {
            return
        }
        let retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.failureRetryInterval))
            guard !Task.isCancelled, let self else {
                return
            }
            guard case .failed = self.states[source] else {
                return
            }
            self.ensureLoad(for: image, baseURL: baseURL)
        }
        retryContexts[source] = FailedLoadRetryContext(attempts: attempts + 1, task: retryTask)
    }

    private static func imageDimensions(from data: Data, fallbackImage: NSImage) -> BlockInputImageDimensions {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return BlockInputImageDimensions(
                width: Int(fallbackImage.size.width.rounded()),
                height: Int(fallbackImage.size.height.rounded())
            )
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int
        if orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8 {
            return BlockInputImageDimensions(width: height, height: width)
        }
        return BlockInputImageDimensions(width: width, height: height)
    }

    /// Non-observing (AppKit) consumers refresh through this notification;
    /// SwiftUI views track `states` through Observation instead.
    private func postStateChange(for source: String) {
        NotificationCenter.default.post(
            name: .appMarkdownImageStateDidChange,
            object: self,
            userInfo: [AppMarkdownImageStore.sourceUserInfoKey: source]
        )
    }
}

extension Notification.Name {
    static let appMarkdownImageStateDidChange = Notification.Name("AppMarkdownImageStateDidChange")
}

extension AppMarkdownImageStore {
    nonisolated static let sourceUserInfoKey = "source"
}

/// Automatic-retry bookkeeping for one failed source: how many self-driven
/// retries ran, and the pending sleep task so a seed can cancel it.
private struct FailedLoadRetryContext {
    let attempts: Int
    let task: Task<Void, Never>
}
