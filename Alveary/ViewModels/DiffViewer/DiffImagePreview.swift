import Foundation

struct DiffImagePreview: Sendable, Equatable, Hashable {
    let old: DiffImageVersion?
    let new: DiffImageVersion?

    var isSplit: Bool {
        old != nil && new != nil
    }
}

struct DiffImageVersion: Sendable, Equatable, Hashable {
    enum Side: String, Sendable {
        case old
        case new
    }

    let source: DiffImageBlobSource
    let side: Side
    let identityPrefix: String
    let fileIdentity: String
    let fileExtension: String
    let needsContentHash: Bool
    /// The exact byte count when the diff already revealed it — a Git LFS pointer states its
    /// object's size, so the auto-load gate can hold a large image back without spending a request
    /// to discover how large it is. Nil whenever only the transport can answer.
    let byteSize: Int?

    init(
        source: DiffImageBlobSource,
        side: Side,
        identityPrefix: String,
        fileIdentity: String,
        fileExtension: String,
        needsContentHash: Bool,
        byteSize: Int? = nil
    ) {
        self.source = source
        self.side = side
        self.identityPrefix = identityPrefix
        self.fileIdentity = fileIdentity
        self.fileExtension = fileExtension
        self.needsContentHash = needsContentHash
        self.byteSize = byteSize
    }

    /// What to call this image in the UI. `fileIdentity` is the path as the diff names it, which is
    /// the only readable name available — a materialized blob's own file name is its cache identity.
    var diffFileName: String {
        URL(fileURLWithPath: fileIdentity).lastPathComponent
    }
}

enum DiffImagePreviewSupport {
    static let maxSourceBytes = 20 * 1024 * 1024
    /// Higher than the checkout ceiling because Git LFS exists to hold files this big, and a
    /// remote fetch only reaches it once the user has explicitly asked for that image.
    static let remoteMaxSourceBytes = 100 * 1024 * 1024
    /// Above this, a slot shows the size and waits for a tap instead of downloading on scroll.
    static let autoLoadByteLimit = 10 * 1024 * 1024
    static let maxPreviewPixelDimension = 2_400
    static let memoryCacheCostLimit = 64 * 1024 * 1024

    /// The byte ceiling a load may reach. Checkout reads keep one flat limit — they cost no
    /// bandwidth, so gating them would only add a click — while remote reads start at the auto-load
    /// gate and rise to the hard cap once confirmed.
    static func byteLimit(for source: DiffImageBlobSource, intent: DiffImageLoadIntent) -> Int {
        switch source {
        case .git:
            return maxSourceBytes
        case .gitHub:
            return intent == .confirmed ? remoteMaxSourceBytes : autoLoadByteLimit
        }
    }

    /// Whether a known size is past the point where confirming could still render the image.
    static func exceedsHardLimit(byteSize: Int, source: DiffImageBlobSource) -> Bool {
        byteSize > byteLimit(for: source, intent: .confirmed)
    }

    private static let imageExtensions: Set<String> = [
        "bmp",
        "gif",
        "heic",
        "heif",
        "icns",
        "jpeg",
        "jpg",
        "png",
        "tif",
        "tiff",
        "webp"
    ]

    static func canPreviewImage(path: String) -> Bool {
        imageExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func syntheticAddedBinaryDiff(for path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        Binary files /dev/null and b/\(path) differ
        """
    }

    static func fileID(for file: DiffFile, fileIndex: Int) -> String {
        let path = file.newPath ?? file.oldPath ?? file.path
        return "\(fileIndex):\(path)"
    }

    static func preview(
        for file: DiffFile,
        fileStatus: FileStatus,
        headHash: String
    ) -> DiffImagePreview? {
        let oldVersion = currentOldVersion(for: file, fileStatus: fileStatus, headHash: headHash)
        let newVersion = currentNewVersion(for: file, fileStatus: fileStatus, headHash: headHash)
        return makePreview(old: oldVersion, new: newVersion)
    }

    static func canPreviewCurrentImage(for file: DiffFile, fileStatus: FileStatus) -> Bool {
        guard file.isBinary else {
            return false
        }

        let oldPath = file.oldPath ?? fileStatus.originalPath ?? file.newPath ?? fileStatus.path
        let newPath = file.newPath ?? fileStatus.path
        let oldIsPreviewable = fileStatus.status != .added
            && fileStatus.status != .untracked
            && canPreviewImage(path: oldPath)
        let newIsPreviewable = fileStatus.status != .deleted
            && canPreviewImage(path: newPath)
        return oldIsPreviewable || newIsPreviewable
    }

    static func preview(
        for file: DiffFile,
        commitHash: String
    ) -> DiffImagePreview? {
        guard file.isBinary else {
            return nil
        }

        let oldVersion = file.oldPath.flatMap { path -> DiffImageVersion? in
            guard canPreviewImage(path: path) else {
                return nil
            }
            return DiffImageVersion(
                source: .git(.commitParent(hash: commitHash, path: path)),
                side: .old,
                identityPrefix: commitHash,
                fileIdentity: path,
                fileExtension: imageExtension(for: path),
                needsContentHash: false
            )
        }

        let newVersion = file.newPath.flatMap { path -> DiffImageVersion? in
            guard canPreviewImage(path: path) else {
                return nil
            }
            return DiffImageVersion(
                source: .git(.commit(hash: commitHash, path: path)),
                side: .new,
                identityPrefix: commitHash,
                fileIdentity: path,
                fileExtension: imageExtension(for: path),
                needsContentHash: false
            )
        }

        return makePreview(old: oldVersion, new: newVersion)
    }

    private static func currentOldVersion(
        for file: DiffFile,
        fileStatus: FileStatus,
        headHash: String
    ) -> DiffImageVersion? {
        let oldPath = file.oldPath ?? fileStatus.originalPath ?? file.newPath ?? fileStatus.path
        guard fileStatus.status != .added,
              fileStatus.status != .untracked,
              canPreviewImage(path: oldPath) else {
            return nil
        }

        let usesIndex = !fileStatus.isStaged
        return DiffImageVersion(
            source: .git(usesIndex ? .index(path: oldPath) : .head(path: oldPath)),
            side: .old,
            identityPrefix: usesIndex ? "\(headHash)-index" : headHash,
            fileIdentity: oldPath,
            fileExtension: imageExtension(for: oldPath),
            needsContentHash: usesIndex
        )
    }

    private static func currentNewVersion(
        for file: DiffFile,
        fileStatus: FileStatus,
        headHash: String
    ) -> DiffImageVersion? {
        let newPath = file.newPath ?? fileStatus.path
        guard fileStatus.status != .deleted,
              canPreviewImage(path: newPath) else {
            return nil
        }

        return DiffImageVersion(
            source: .git(fileStatus.isStaged ? .index(path: newPath) : .worktree(path: newPath)),
            side: .new,
            identityPrefix: fileStatus.isStaged ? "\(headHash)-index" : "\(headHash)-worktree",
            fileIdentity: newPath,
            fileExtension: imageExtension(for: newPath),
            needsContentHash: true
        )
    }

    private static func makePreview(old: DiffImageVersion?, new: DiffImageVersion?) -> DiffImagePreview? {
        guard old != nil || new != nil else {
            return nil
        }
        return DiffImagePreview(old: old, new: new)
    }

    static func imageExtension(for path: String) -> String {
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return pathExtension.isEmpty ? "img" : pathExtension
    }
}
