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

    let source: GitImageBlobSource
    let side: Side
    let identityPrefix: String
    let fileIdentity: String
    let fileExtension: String
    let needsContentHash: Bool
}

enum DiffImagePreviewSupport {
    static let maxSourceBytes = 20 * 1024 * 1024
    static let maxPreviewPixelDimension = 2_400
    static let memoryCacheCostLimit = 64 * 1024 * 1024

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
                source: .commitParent(hash: commitHash, path: path),
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
                source: .commit(hash: commitHash, path: path),
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
            source: usesIndex ? .index(path: oldPath) : .head(path: oldPath),
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
            source: fileStatus.isStaged ? .index(path: newPath) : .worktree(path: newPath),
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

    private static func imageExtension(for path: String) -> String {
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return pathExtension.isEmpty ? "img" : pathExtension
    }
}
