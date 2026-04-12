import CoreServices
import Foundation

private let diffViewerFSEventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
    DiffViewerWatchController.handleWatchEventCallback(
        info: info,
        count: numEvents,
        eventPaths: eventPaths
    )
}

private final class DiffViewerWatchContext {
    weak var owner: DiffViewerWatchController?
    let rootDirectory: String

    init(owner: DiffViewerWatchController, rootDirectory: String) {
        self.owner = owner
        self.rootDirectory = rootDirectory
    }
}

@MainActor
final class DiffViewerWatchController {
    private let fsEventDebounceDuration: Duration
    private let idlePollInterval: Duration
    private let onIdlePoll: @MainActor (String) async -> Void
    private let onFSRefresh: @MainActor (String, Set<String>) async -> Void

    private var activeDirectory: String?
    private var fsEventStream: FSEventStreamRef?
    private var fsEventQueue: DispatchQueue?
    private var watchContextRetain: Unmanaged<DiffViewerWatchContext>?
    private var debounceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var pendingChangedPaths: Set<String> = []

    init(
        fsEventDebounceDuration: Duration,
        idlePollInterval: Duration,
        onIdlePoll: @escaping @MainActor (String) async -> Void,
        onFSRefresh: @escaping @MainActor (String, Set<String>) async -> Void
    ) {
        self.fsEventDebounceDuration = fsEventDebounceDuration
        self.idlePollInterval = idlePollInterval
        self.onIdlePoll = onIdlePoll
        self.onFSRefresh = onFSRefresh
    }

    func startWatching(_ directory: String) {
        stopWatching()
        activeDirectory = directory

        let paths = [directory] as CFArray
        var context = FSEventStreamContext()
        let retainedContext = Unmanaged.passRetained(DiffViewerWatchContext(owner: self, rootDirectory: directory))
        watchContextRetain = retainedContext
        context.info = retainedContext.toOpaque()

        let stream = FSEventStreamCreate(
            nil,
            diffViewerFSEventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream {
            let queue = DispatchQueue(label: "com.afollestad.alveary.fsevents", qos: .utility)
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            fsEventStream = stream
            fsEventQueue = queue
        } else {
            retainedContext.release()
            watchContextRetain = nil
        }

        let idlePollInterval = self.idlePollInterval
        pollTask = Task { @MainActor [weak self, idlePollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: idlePollInterval)
                guard !Task.isCancelled else {
                    break
                }
                guard let self, let directory = self.activeDirectory else {
                    continue
                }
                await self.onIdlePoll(directory)
            }
        }
    }

    func stopWatching() {
        activeDirectory = nil
        pendingChangedPaths = []
        debounceTask?.cancel()
        debounceTask = nil
        pollTask?.cancel()
        pollTask = nil

        if let stream = fsEventStream, let queue = fsEventQueue {
            FSEventStreamStop(stream)
            queue.sync {
                FSEventStreamInvalidate(stream)
            }
            FSEventStreamRelease(stream)
            fsEventStream = nil
            fsEventQueue = nil
        }

        if let watchContextRetain {
            watchContextRetain.release()
            self.watchContextRetain = nil
        }
    }

    func handleFSEventsForTesting(changedPaths: Set<String>, directory: String) {
        fsEventsDidFire(changedPaths: changedPaths, directoryOverride: directory)
    }

    private func fsEventsDidFire(changedPaths: Set<String>, directoryOverride: String? = nil) {
        debounceTask?.cancel()
        pendingChangedPaths.formUnion(changedPaths)
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: fsEventDebounceDuration)
            guard !Task.isCancelled else {
                return
            }
            guard let directory = directoryOverride ?? activeDirectory else {
                return
            }

            let changedPaths = pendingChangedPaths
            pendingChangedPaths = []
            await onFSRefresh(directory, changedPaths)
        }
    }

    nonisolated private static func extractChangedPaths(
        eventPaths: UnsafeMutableRawPointer?,
        count: Int,
        rootDirectory: String?
    ) -> Set<String> {
        guard let rootDirectory,
              let eventPaths else {
            return []
        }

        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
        let rootPrefix = rootDirectory.hasSuffix("/") ? rootDirectory : rootDirectory + "/"
        return Set(paths.prefix(count).map { absolutePath in
            guard absolutePath.hasPrefix(rootPrefix) else {
                return absolutePath
            }
            return String(absolutePath.dropFirst(rootPrefix.count))
        })
    }

    nonisolated fileprivate static func handleWatchEventCallback(
        info: UnsafeMutableRawPointer?,
        count: Int,
        eventPaths: UnsafeMutableRawPointer?
    ) {
        guard let info else {
            return
        }

        let watchContext = Unmanaged<DiffViewerWatchContext>.fromOpaque(info).takeUnretainedValue()
        let changedPaths = extractChangedPaths(
            eventPaths: eventPaths,
            count: count,
            rootDirectory: watchContext.rootDirectory
        )

        dispatchWatchEvent(changedPaths: changedPaths, owner: watchContext.owner)
    }

    nonisolated private static func dispatchWatchEvent(
        changedPaths: Set<String>,
        owner: DiffViewerWatchController?
    ) {
        guard let owner else {
            return
        }

        Task { @MainActor [weak owner] in
            owner?.fsEventsDidFire(changedPaths: changedPaths)
        }
    }
}
