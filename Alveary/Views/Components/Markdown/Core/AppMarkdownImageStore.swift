import AppKit
import BlockInputKit
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
        case failed
    }

    private(set) var states: [String: ImageState] = [:]

    @ObservationIgnored private let loader: any BlockInputImageLoading
    @ObservationIgnored private let diskCache: (any BlockInputImageDiskCaching)?
    @ObservationIgnored private var loadTasks: [String: Task<Void, Never>] = [:]

    private static let maximumSourceBytes = 20 * 1024 * 1024
    private static let maximumPixelDimension = 8_192

    init(
        loader: any BlockInputImageLoading = BlockInputDefaultImageLoader(),
        diskCache: (any BlockInputImageDiskCaching)? = BlockInputDefaultImageDiskCache()
    ) {
        self.loader = loader
        self.diskCache = diskCache
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

    /// Starts a load unless one already finished or is in flight. Keyed by the
    /// raw source string; callers resolve relative sources before asking.
    func ensureLoad(for image: BlockInputImage, baseURL: URL?) {
        let source = image.source
        guard states[source] == nil else {
            return
        }
        guard let resolvedURL = AppMarkdownImageSourceResolver.resolvedURL(for: source, baseURL: baseURL) else {
            states[source] = .failed
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
        let loader = loader
        loadTasks[source] = Task { [weak self] in
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
                await MainActor.run {
                    self?.finishLoadFailure(source: source)
                }
            }
        }
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
            finishLoadFailure(source: source)
            return
        }
        states[source] = .loaded(nsImage)
        postStateChange(for: source)
    }

    private func finishLoadFailure(source: String) {
        loadTasks[source] = nil
        states[source] = .failed
        postStateChange(for: source)
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
