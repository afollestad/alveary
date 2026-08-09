#if DEBUG
import Foundation

/// The attachment payload for a demo conversation that carries images, and optionally an app shot
/// and a file chip.
struct DemoAttachments {
    static let empty = DemoAttachments(images: [], appShots: [], files: [])

    let images: [LocalImageAttachment]
    let appShots: [PersistedAppShotAttachment]
    let files: [LocalFileAttachment]
}

/// What one conversation's attachment strip should contain, resolved against the bundled
/// `DemoAssets/` PNGs.
struct DemoAttachmentRequest {
    struct AppShot {
        let assetName: String
        let appName: String
        let bundleIdentifier: String
        let windowTitle: String
        let axTreeText: String
    }

    struct Note {
        let fileName: String
        let markdown: String
    }

    /// `DemoAssets/<name>.png`, in the order the tiles should render.
    let imageAssetNames: [String]
    let appShot: AppShot?
    let note: Note?
}

@MainActor
extension DemoDataSeeder {
    /// Copies the Debug-only bundled PNGs into the demo profile's attachment store and describes
    /// them the way the transcript expects.
    ///
    /// The files have to genuinely exist: tiles load through `NSImage(contentsOf:)`, and a missing
    /// one draws an empty rounded rect rather than failing loudly. The wipe-on-launch storage
    /// factory clears the copies along with everything else.
    static func prepareAttachments(
        _ request: DemoAttachmentRequest,
        conversationID: String,
        attachmentsDirectory: URL,
        fileManager: FileManager = .default
    ) -> DemoAttachments {
        let conversationDirectory = attachmentsDirectory
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(conversationID, isDirectory: true)

        let images = request.imageAssetNames.compactMap { name in
            copyBundledAsset(name, into: conversationDirectory, fileManager: fileManager)
                .map { attachment(at: $0, label: "\(name).png") }
        }
        guard images.count == request.imageAssetNames.count else {
            return .empty
        }

        return DemoAttachments(
            images: images,
            appShots: persistedAppShots(request.appShot, in: conversationDirectory, fileManager: fileManager),
            files: files(request.note, in: conversationDirectory, fileManager: fileManager)
        )
    }

    /// The trip-sharing thread's design attachments: the share sheet the work is building and the
    /// itinerary a shared link opens onto. They ride a mid-transcript message rather than the
    /// opening brief, so the thread starts on the request rather than on a strip of tiles.
    static let tripSharingDesignAttachmentRequest = DemoAttachmentRequest(
        imageAssetNames: ["share-sheet-mock", "trip-itinerary"],
        appShot: nil,
        note: nil
    )

    /// A capture of the running trip screen, on its own message beneath the designs.
    static let tripSharingCaptureAttachmentRequest = DemoAttachmentRequest(
        imageAssetNames: [],
        appShot: DemoAttachmentRequest.AppShot(
            assetName: "waypoint-trip-window",
            appName: "Waypoint",
            bundleIdentifier: "app.waypoint.mac",
            windowTitle: "Kyoto, five days — Waypoint",
            axTreeText: "Window \"Kyoto, five days — Waypoint\"\n  Group \"Itinerary\"\n    Button \"Share trip\""
        ),
        note: nil
    )

    /// The empty-states thread carries every attachment kind, split across two messages: stacking
    /// image tiles, a file chip, and an app-shot card on one bubble reads as a pile rather than as
    /// two separate things the user sent. File chips render only on a `user` message, which is why
    /// the note rides the design bubble rather than standing alone.
    static let emptyStatesDesignAttachmentRequest = DemoAttachmentRequest(
        imageAssetNames: ["empty-states-mock", "map-tile-gap"],
        appShot: nil,
        note: DemoAttachmentRequest.Note(
            fileName: "empty-state-copy.md",
            markdown: """
                # Empty state copy

                - Search: "No trips match that search."
                - History: "Trips you finish show up here."
                - Shared: "Links people send you land here."
                """
        )
    )

    static let emptyStatesCaptureAttachmentRequest = DemoAttachmentRequest(
        imageAssetNames: [],
        appShot: DemoAttachmentRequest.AppShot(
            assetName: "waypoint-window",
            appName: "Waypoint",
            bundleIdentifier: "app.waypoint.mac",
            windowTitle: "Search — Waypoint",
            axTreeText: "Window \"Search — Waypoint\"\n  Group \"Results\"\n    StaticText \"Nothing here\""
        ),
        note: nil
    )

    private static func persistedAppShots(
        _ appShot: DemoAttachmentRequest.AppShot?,
        in conversationDirectory: URL,
        fileManager: FileManager
    ) -> [PersistedAppShotAttachment] {
        guard let appShot else {
            return []
        }
        let appShotDirectory = conversationDirectory.appendingPathComponent("appshots", isDirectory: true)
        guard let url = copyBundledAsset(appShot.assetName, into: appShotDirectory, fileManager: fileManager) else {
            return []
        }
        return [
            PersistedAppShotAttachment(
                screenshot: attachment(at: url, label: "\(appShot.windowTitle).png"),
                appName: appShot.appName,
                bundleIdentifier: appShot.bundleIdentifier,
                windowTitle: appShot.windowTitle,
                axTreeText: appShot.axTreeText
            )
        ]
    }

    /// The file chip needs a real file too, and a short Markdown note is more legible in a
    /// screenshot than another image.
    private static func files(
        _ note: DemoAttachmentRequest.Note?,
        in conversationDirectory: URL,
        fileManager: FileManager
    ) -> [LocalFileAttachment] {
        guard let note else {
            return []
        }
        let destinationURL = conversationDirectory.appendingPathComponent(note.fileName, isDirectory: false)
        do {
            try fileManager.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
            try note.markdown.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            return []
        }
        return [LocalFileAttachment(fileURL: destinationURL, label: note.fileName)]
    }

    private static func copyBundledAsset(
        _ name: String,
        into directory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let sourceURL = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "DemoAssets"
        ) else {
            return nil
        }
        let destinationURL = directory.appendingPathComponent("\(name).png", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            return nil
        }
        return destinationURL
    }

    private static func attachment(at url: URL, label: String) -> LocalImageAttachment {
        LocalImageAttachment(
            id: url.deletingPathExtension().lastPathComponent,
            fileURL: url,
            label: label,
            createdAt: DemoData.hoursAgo(8)
        )
    }
}
#endif
