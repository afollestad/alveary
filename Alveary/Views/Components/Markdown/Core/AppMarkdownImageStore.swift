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

    /// Keyed by `storageKey(for:baseURL:)`, never by the raw source. Two
    /// transcript rows under different base URLs can both say
    /// `![x](images/diagram.png)`, and a raw-source key would hand each the
    /// other's bitmap and the other's dimensions.
    private(set) var states: [String: ImageState] = [:]

    /// Real pixel dimensions per key, so a display box can wrap the bitmap
    /// before it is decoded. Deliberately not observation-tracked: the file
    /// probe below fills it synchronously *during* a SwiftUI `body`, and an
    /// observed mutation there would re-enter the render pass. A remote source
    /// lands here only via a load, which flips observed `states` in the same
    /// turn and drives the refresh instead — but only for a view that reads
    /// `states`. A SwiftUI view that sizes itself from `naturalSize(for:)` alone
    /// registers no dependency and, if its own stored properties are unchanged
    /// across the load, is never re-evaluated: it keeps the pre-load box and
    /// squeezes the bitmap into it. Resolve such a box in a parent that reads
    /// load state and pass the size down.
    @ObservationIgnored private var naturalSizes: [String: CGSize] = [:]
    /// Keys whose file probe already ran, so a source that has no readable
    /// header is not re-probed on every layout pass.
    @ObservationIgnored private var probedFileKeys: Set<String> = []

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

    func image(forSource source: String, baseURL: URL? = nil) -> NSImage? {
        guard case let .loaded(image) = states[storageKey(forSource: source, baseURL: baseURL)] else {
            return nil
        }
        return image
    }

    func hasFailed(source: String, baseURL: URL? = nil) -> Bool {
        guard case .failed = states[storageKey(forSource: source, baseURL: baseURL)] else {
            return false
        }
        return true
    }

    /// Identity for one image's bytes: the resolved absolute URL, so a relative
    /// source means different things under different base URLs. Falls back to
    /// the raw source when nothing resolves, which is also what `ensureLoad`
    /// records the permanent failure under.
    func storageKey(forSource source: String, baseURL: URL?) -> String {
        AppMarkdownImageSourceResolver.resolvedURL(for: source, baseURL: baseURL)?.absoluteString ?? source
    }

    /// Real pixel dimensions for a source, or `nil` when they cannot be known
    /// yet. Renderers resolve through this before sizing so an image block
    /// reserves the box the bitmap will actually occupy — reacting to a decoded
    /// bitmap instead would shift the transcript on every load.
    ///
    /// A local source is answered on the spot: `CGImageSourceCopyPropertiesAtIndex`
    /// reads header metadata without decoding, and the result is memoized, so
    /// repeat layout passes cost a dictionary lookup. A remote source answers
    /// `nil` until its load lands; callers fall back to
    /// `appMarkdownImageDefaultAspectRatio` for that one render.
    func naturalSize(for image: BlockInputImage, baseURL: URL?) -> CGSize? {
        // Declared dimensions win in `appMarkdownResolved(naturalSize:)`, so
        // probing the file for them would be wasted I/O.
        guard image.width == nil || image.height == nil else {
            return nil
        }
        let key = storageKey(forSource: image.source, baseURL: baseURL)
        // Every path that stores a `.loaded` state also records here, so a
        // loaded bitmap always answers from this map.
        if let known = naturalSizes[key] {
            return known
        }
        guard !probedFileKeys.contains(key),
              let resolvedURL = AppMarkdownImageSourceResolver.resolvedURL(for: image.source, baseURL: baseURL),
              resolvedURL.isFileURL else {
            return nil
        }
        probedFileKeys.insert(key)
        guard let probed = Self.probedNaturalSize(atFileURL: resolvedURL) else {
            // A file the agent has not written yet reads as unprobeable. It is
            // not re-probed per layout pass; `ensureLoad`'s retry records the
            // size through `finishLoad` once the file exists.
            return nil
        }
        naturalSizes[key] = probed
        return probed
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
        let stateKey = storageKey(forSource: source, baseURL: nil)
        loadTasks[stateKey]?.cancel()
        loadTasks[stateKey] = nil
        cancelAutomaticRetry(for: stateKey)
        let dimensions = Self.imageDimensions(from: data, fallbackImage: nsImage)
        recordNaturalSize(dimensions, for: stateKey)
        states[stateKey] = .loaded(nsImage)
        postStateChange(for: stateKey)

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
        let entry = BlockInputImageDiskCacheEntry(data: data, dimensions: dimensions)
        try? await diskCache.storeImage(entry, forKey: key)
    }

    /// Starts a load unless one already finished or is in flight. A failed
    /// source becomes loadable again after `failureRetryInterval` — a remote
    /// image that 404s can start existing later (GitHub attachments stay
    /// session-gated until their embedding content is saved).
    func ensureLoad(for image: BlockInputImage, baseURL: URL?) {
        let key = storageKey(forSource: image.source, baseURL: baseURL)
        guard shouldAttemptLoad(of: key) else {
            return
        }
        guard let resolvedURL = AppMarkdownImageSourceResolver.resolvedURL(for: image.source, baseURL: baseURL) else {
            // Unresolvable sources are permanent failures; a retry cannot help.
            states[key] = .failed(.distantFuture)
            return
        }
        states[key] = .loading
        let request = BlockInputImageLoadRequest(
            image: image,
            resolvedURL: resolvedURL,
            cacheKey: image.cacheKey(resolvedURL: resolvedURL, maximumPixelDimension: Self.maximumPixelDimension),
            maxSourceBytes: Self.maximumSourceBytes,
            maxPixelDimension: Self.maximumPixelDimension,
            diskCache: diskCache
        )
        loadTasks[key] = makeLoadTask(request: request, image: image, baseURL: baseURL, key: key)
    }

    private func shouldAttemptLoad(of key: String) -> Bool {
        switch states[key] {
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
        baseURL: URL?,
        key: String
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
                    self?.finishLoad(loaded, key: key)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if let fallbackLoaded = await self?.loadThroughFallbackURL(request: request, source: source) {
                    await MainActor.run {
                        self?.finishLoad(fallbackLoaded, key: key)
                    }
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoadFailure(key: key, image: image, baseURL: baseURL)
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
    func preloadForTesting(source: String, image: NSImage, baseURL: URL? = nil) {
        let key = storageKey(forSource: source, baseURL: baseURL)
        naturalSizes[key] = image.size
        states[key] = .loaded(image)
    }

    /// Compact digest of what this store knows about every image source in the
    /// markdown. Measurement caches must include it in their keys: an inline
    /// image growing from alt text to a bitmap changes measured heights, and a
    /// block image's box changes the moment its real dimensions resolve.
    ///
    /// Resolving the sizes here rather than reporting only load state is what
    /// keeps the key honest — it has to already reflect the size the measurer
    /// is about to compute, or the first measurement caches under a key that
    /// the next pass no longer asks for.
    func loadStateFingerprint(forMarkdown markdown: String, baseURL: URL? = nil) -> String {
        guard markdown.contains("![") || markdown.range(of: "<img", options: .caseInsensitive) != nil else {
            return ""
        }
        return loadStateFingerprint(
            forImages: AppMarkdownImageSyntaxParser.imageMatchesOutsideCode(in: markdown).map(\.image),
            baseURL: baseURL
        )
    }

    /// The same digest for callers holding already-parsed images rather than the markdown that
    /// produced them — the SwiftUI table's grid layout caches column widths across passes and
    /// only its cells' images can change them.
    func loadStateFingerprint(forImages images: [BlockInputImage], baseURL: URL? = nil) -> String {
        images
            .map { image in
                let stateMark: String
                switch states[storageKey(forSource: image.source, baseURL: baseURL)] {
                case .none:
                    stateMark = "n"
                case .loading:
                    stateMark = "p"
                case .failed:
                    stateMark = "f"
                case .loaded:
                    stateMark = "l"
                }
                guard let size = naturalSize(for: image, baseURL: baseURL) else {
                    return stateMark
                }
                return "\(stateMark)\(Int(size.width))x\(Int(size.height))"
            }
            .joined(separator: ",")
    }

    private func finishLoad(_ loaded: BlockInputLoadedImage, key: String) {
        loadTasks[key] = nil
        guard let nsImage = NSImage(data: loaded.data), nsImage.size.width > 0, nsImage.size.height > 0 else {
            finishLoadFailure(key: key, image: nil, baseURL: nil)
            return
        }
        cancelAutomaticRetry(for: key)
        // The loader already corrected these for EXIF orientation; `NSImage.size`
        // reports points and would disagree with a DPI-tagged source.
        recordNaturalSize(loaded.dimensions, for: key)
        states[key] = .loaded(nsImage)
        postStateChange(for: key)
    }

    /// Records dimensions a load resolved, overriding an earlier probe miss.
    private func recordNaturalSize(_ dimensions: BlockInputImageDimensions, for key: String) {
        naturalSizes[key] = CGSize(width: dimensions.width, height: dimensions.height)
    }

    private func cancelAutomaticRetry(for key: String) {
        retryContexts[key]?.task.cancel()
        retryContexts[key] = nil
    }

    private func finishLoadFailure(key: String, image: BlockInputImage?, baseURL: URL?) {
        loadTasks[key] = nil
        states[key] = .failed(now())
        postStateChange(for: key)
        if let image {
            scheduleAutomaticRetry(for: image, baseURL: baseURL, key: key)
        }
    }

    /// A visible failure block re-renders only when something else invalidates
    /// it, so `ensureLoad`'s retry window alone leaves a broken image broken on
    /// an untouched screen. A couple of self-driven retries heal it in place.
    private func scheduleAutomaticRetry(for image: BlockInputImage, baseURL: URL?, key: String) {
        let attempts = retryContexts[key]?.attempts ?? 0
        guard attempts < Self.maximumAutomaticRetries else {
            return
        }
        let retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.failureRetryInterval))
            guard !Task.isCancelled, let self else {
                return
            }
            guard case .failed = self.states[key] else {
                return
            }
            self.ensureLoad(for: image, baseURL: baseURL)
        }
        retryContexts[key] = FailedLoadRetryContext(attempts: attempts + 1, task: retryTask)
    }

    private static func imageDimensions(from data: Data, fallbackImage: NSImage) -> BlockInputImageDimensions {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dimensions = imageDimensions(fromProperties: properties) else {
            return BlockInputImageDimensions(
                width: Int(fallbackImage.size.width.rounded()),
                height: Int(fallbackImage.size.height.rounded())
            )
        }
        return dimensions
    }

    /// Header-only dimension read for a file source. `kCGImageSourceShouldCache`
    /// keeps ImageIO from decoding the bitmap, which is what makes this cheap
    /// enough to call from a layout pass.
    private static func probedNaturalSize(atFileURL url: URL) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let dimensions = imageDimensions(fromProperties: properties) else {
            return nil
        }
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    /// Shared by the probe and the load path so a probed size and a loaded one
    /// cannot disagree about orientation.
    private static func imageDimensions(fromProperties properties: [CFString: Any]) -> BlockInputImageDimensions? {
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int
        if orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8 {
            return BlockInputImageDimensions(width: height, height: width)
        }
        return BlockInputImageDimensions(width: width, height: height)
    }

    /// Non-observing (AppKit) consumers refresh through this notification;
    /// SwiftUI views track `states` through Observation instead. The payload is
    /// a `storageKey(forSource:baseURL:)`, so an observer must derive the same
    /// key rather than compare against its raw markdown source.
    private func postStateChange(for key: String) {
        NotificationCenter.default.post(
            name: .appMarkdownImageStateDidChange,
            object: self,
            userInfo: [AppMarkdownImageStore.storageKeyUserInfoKey: key]
        )
    }
}

extension Notification.Name {
    static let appMarkdownImageStateDidChange = Notification.Name("AppMarkdownImageStateDidChange")
}

extension AppMarkdownImageStore {
    nonisolated static let storageKeyUserInfoKey = "storageKey"
}

/// Automatic-retry bookkeeping for one failed source: how many self-driven
/// retries ran, and the pending sleep task so a seed can cancel it.
private struct FailedLoadRetryContext {
    let attempts: Int
    let task: Task<Void, Never>
}
